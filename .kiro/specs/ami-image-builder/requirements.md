# Requirements Document

## Introduction

Define the Terraform infrastructure for an EC2 Image Builder pipeline that produces golden AMIs for the devbox pool. The pipeline builds Amazon Linux 2023 images with pre-installed development tooling, publishes the resulting AMI ID to SSM Parameter Store, and runs in the egress VPC (which has NAT gateway internet access) while producing AMIs usable by the workload VPC's Auto Scaling Group. This spec covers the Terraform modules, IAM roles, networking configuration, component definitions, distribution settings, and lifecycle management needed to operate the pipeline within the existing devbox-infra repository structure.

## Glossary

- **Image_Builder_Pipeline**: An EC2 Image Builder pipeline resource (`aws_imagebuilder_pipeline`) that orchestrates scheduled or on-demand AMI builds by combining an Image_Recipe with Infrastructure_Configuration and Distribution_Configuration
- **Image_Recipe**: An EC2 Image Builder image recipe (`aws_imagebuilder_image_recipe`) that specifies the base AMI (Amazon Linux 2023) and an ordered list of Components to apply during the build
- **Component**: An EC2 Image Builder component (`aws_imagebuilder_component`) defined in AWSTOE YAML format that encapsulates a discrete provisioning step (e.g., install packages, configure services)
- **Infrastructure_Configuration**: An EC2 Image Builder infrastructure configuration (`aws_imagebuilder_infrastructure_configuration`) that defines the instance type, subnet, security group, IAM role, and logging settings for build instances
- **Distribution_Configuration**: An EC2 Image Builder distribution configuration (`aws_imagebuilder_distribution_configuration`) that defines AMI naming, target regions, tags, and launch permissions for output AMIs
- **Egress_VPC**: The VPC with NAT gateway internet access (CIDR 10.1.0.0/16) where Image Builder instances run to download packages
- **Workload_VPC**: The private-only VPC (CIDR 10.0.0.0/16) where devbox pool instances run, with no direct internet access
- **SSM_Parameter**: An AWS Systems Manager Parameter Store parameter that stores the latest AMI ID for consumption by the pool manager
- **Build_Instance_Role**: An IAM instance profile and role attached to Image Builder build instances, granting permissions for package installation, S3 access, SSM communication, and AMI creation
- **Pipeline_Execution_Role**: An IAM role used by the Image Builder service to manage pipeline execution, create AMIs, and write to SSM Parameter Store
- **Golden_AMI**: The output AMI produced by a successful pipeline execution, containing all pre-baked software and configuration
- **AMI_Lifecycle_Policy**: An Image Lifecycle Policy that automatically deregisters and deletes old AMIs and their associated snapshots after a retention period

## Requirements

### Requirement 1: Image Builder Pipeline Terraform Module

**User Story:** As a platform operator, I want a reusable Terraform module that provisions an EC2 Image Builder pipeline, so that I can manage AMI builds declaratively alongside the rest of the devbox infrastructure.

#### Acceptance Criteria

1. THE module SHALL create an `aws_imagebuilder_pipeline` resource with a configurable name prefix, schedule (cron expression), and enhanced image metadata collection enabled
2. THE module SHALL create an `aws_imagebuilder_image_recipe` resource that references the latest Amazon Linux 2023 kernel 6.18 AMI (via SSM parameter `/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.18-x86_64`) as the parent image, ensuring builds always use the most recent AL2023 base with the 6.18 kernel
3. THE module SHALL accept a list of component ARNs as an input variable and attach them to the Image_Recipe in the specified order
4. THE module SHALL create an `aws_imagebuilder_infrastructure_configuration` resource that references the Build_Instance_Role, a configurable instance type (default `m5.large`), the Egress_VPC subnet, and a dedicated security group
5. THE module SHALL create an `aws_imagebuilder_distribution_configuration` resource that distributes the Golden_AMI to the current region (`us-east-1`) with a configurable name pattern including the build date
6. THE module SHALL configure the pipeline to publish build logs to a CloudWatch Log Group with a configurable retention period (default 30 days)
7. THE module SHALL follow the repository conventions by placing resource definitions in `main.tf`, variables in `variables.tf`, outputs in `outputs.tf`, and locals in `locals.tf`

### Requirement 2: Build Instance Networking

**User Story:** As a platform operator, I want Image Builder build instances to run in the egress VPC with internet access, so that they can download packages via yum, pip, and other package managers during the AMI build process.

#### Acceptance Criteria

1. THE Infrastructure_Configuration SHALL place build instances in a private subnet of the Egress_VPC that routes outbound traffic through the NAT gateway
2. THE module SHALL create a dedicated security group in the Egress_VPC for build instances that allows all outbound traffic (egress to 0.0.0.0/0 on all ports) and no inbound traffic from external sources
3. THE security group SHALL require inbound traffic rules from itself (self-referencing rule) to support multi-instance test scenarios within Image Builder; the security group SHALL NOT be created without this self-referencing rule
4. THE module SHALL accept the Egress_VPC ID and subnet IDs as input variables, sourced from the existing `module.egress` outputs in the environment configuration
5. WHEN the build instance launches, THE Infrastructure_Configuration SHALL configure the instance with IMDSv2 required (http_tokens = "required") for metadata access security

### Requirement 3: Build Instance IAM Role

**User Story:** As a platform operator, I want a least-privilege IAM role for Image Builder build instances, so that builds can install software and create AMIs without excessive permissions.

#### Acceptance Criteria

1. THE module SHALL create an IAM role with an assume-role policy that allows the `ec2.amazonaws.com` service principal to assume it
2. THE module SHALL attach the AWS-managed policy `EC2InstanceProfileForImageBuilder` to the Build_Instance_Role for base Image Builder functionality
3. THE module SHALL attach the AWS-managed policy `AmazonSSMManagedInstanceCore` to the Build_Instance_Role for SSM-based instance management during builds
4. THE module SHALL create a custom IAM policy that grants `s3:GetObject` permission on the specific S3 bucket path containing component manifests and build artifacts
5. THE module SHALL create an instance profile wrapping the Build_Instance_Role and reference it in the Infrastructure_Configuration
6. THE Build_Instance_Role SHALL NOT have permissions to modify IAM policies, create IAM roles, or access production databases
7. IF the build requires access to private Git repositories, THEN THE Build_Instance_Role SHALL have permission to read specific AWS Secrets Manager secrets (configurable ARN list) for authentication tokens

### Requirement 4: AMI Distribution and Output Configuration

**User Story:** As a platform operator, I want the pipeline to distribute the AMI to the correct region with consistent naming and tagging, so that the output is discoverable and traceable.

#### Acceptance Criteria

1. THE Distribution_Configuration SHALL distribute the Golden_AMI to `us-east-1` with an AMI name pattern of `devbox-golden-{{imagebuilder:buildDate}}` to ensure unique naming per build
2. THE Distribution_Configuration SHALL apply tags to the output AMI including: `Environment` = var.environment, `ManagedBy` = "terraform", `Pipeline` = "ami-image-builder", `BuildDate` = "{{imagebuilder:buildDate}}", and `SourceAMI` = "{{imagebuilder:parentImage}}"
3. THE Distribution_Configuration SHALL configure the output AMI with launch permissions restricted to the owning AWS account by default, with an optional `trusted_account_ids` variable (list of AWS account IDs) to allow cross-account sharing; WHEN trusted accounts are specified, THE Distribution_Configuration SHALL copy the AMI to those accounts using native Image Builder cross-account distribution
4. THE Distribution_Configuration SHALL accept an optional `distribution_regions` variable (list of AWS region strings, default empty) to copy the AMI to additional regions using native Image Builder cross-region distribution
4. THE module SHALL configure EBS volume encryption on the output AMI using the default AWS-managed KMS key (`aws/ebs`)
5. THE module SHALL output the Distribution_Configuration ARN and the pipeline ARN as Terraform outputs for reference by other modules

### Requirement 5: SSM Parameter Store Publication

**User Story:** As a platform operator, I want the pipeline to publish the new AMI ID to SSM Parameter Store upon successful build, so that the pool manager can discover new AMIs without manual intervention.

#### Acceptance Criteria

1. THE Distribution_Configuration SHALL include an `ssm_parameter_configuration` block that writes the output AMI ID to the SSM parameter at path `/devbox/ami/latest` with data type `aws:ec2:image`, enabling native AMI ID publication without external automation
2. THE module SHALL create an SSM Parameter resource at path `/devbox/ami/latest` with type `String` and data type `aws:ec2:image`, with an initial value of the base AMI ID (to be overwritten by pipeline executions)
3. THE module SHALL grant the Image Builder execution role `ssm:PutParameter` permission on the `/devbox/ami/latest` parameter ARN so that the distribution step can write the AMI ID natively
4. THE module SHALL output the SSM parameter name and ARN as Terraform outputs so the pool manager deployment can reference them
5. THE SSM parameter SHALL be tagged with `Environment`, `ManagedBy`, and `Pipeline` tags consistent with the rest of the infrastructure

### Requirement 6: Build Schedule and Trigger Configuration

**User Story:** As a platform operator, I want to control when AMI builds run through configurable schedules and triggers, so that I can balance image freshness against build costs.

#### Acceptance Criteria

1. THE Image_Builder_Pipeline SHALL accept a schedule variable with a cron expression (default: `cron(0 2 ? * SUN *)` for weekly Sunday at 02:00 UTC) and a pipeline_execution_start_condition of `EXPRESSION_MATCH_AND_DEPENDENCY_UPDATES_AVAILABLE`
2. THE module SHALL accept a boolean variable `schedule_enabled` (default true) that controls whether the automatic schedule is active, allowing manual-only operation
3. WHEN the schedule is disabled, THE Image_Builder_Pipeline SHALL only execute via manual trigger through the AWS Console, CLI (`start-image-pipeline-execution`), or API
4. THE module SHALL create an EventBridge rule (configurable, disabled by default) that triggers a pipeline execution when an S3 object is uploaded to a configurable manifest bucket path, enabling event-driven builds
5. THE Image_Builder_Pipeline SHALL configure `image_tests_configuration` with `image_tests_enabled = true` and a configurable timeout (default 60 minutes) to validate AMIs before distribution

### Requirement 7: Modular Component Design

**User Story:** As a platform operator, I want Image Builder components defined as separate, composable Terraform resources, so that I can independently version, test, and reorder provisioning steps.

#### Acceptance Criteria

1. THE module SHALL define each Component as a separate `aws_imagebuilder_component` resource with its own AWSTOE YAML document, platform set to "Linux", and a semantic version number
2. THE module SHALL organize components in a logical execution order: (1) base OS updates, (2) development tools, (3) language runtimes, (4) container tooling, (5) agent dependencies, (6) repository cloning, (7) warm-up daemon, (8) SSH configuration, (9) security hardening
3. THE module SHALL accept the component YAML documents as file paths (relative to the module) using the `templatefile()` function to allow variable interpolation within component documents
4. WHEN a component's YAML content changes (detected via content hash), THE module SHALL create a new component version resource (Image Builder components are immutable once created) and update the Image_Recipe to reference the new version, leaving the version incremented for retry on next deployment if creation fails
5. THE module SHALL define a test component that validates the image after build by verifying installed tool versions, service status, and user configuration
6. THE module SHALL tag each Component resource with a `ComponentOrder` tag indicating its position in the recipe for operational clarity

### Requirement 8: AMI Lifecycle and Cost Management

**User Story:** As a platform operator, I want old AMIs automatically cleaned up and build resources right-sized, so that I control costs without manual intervention.

#### Acceptance Criteria

1. THE module SHALL create an `aws_imagebuilder_lifecycle_policy` resource that retains at most 5 AMI versions and automatically deregisters older ones, deleting their associated EBS snapshots and volumes
2. THE lifecycle policy SHALL retain at least the 5 most recent AMI versions regardless of age to ensure rollback capability
3. THE lifecycle policy SHALL exclude AMIs tagged with `devbox:status` = "production" or `devbox:keep` = "true" from automatic deletion
4. THE module SHALL accept a `build_instance_type` variable (default `m5.large`) to allow cost optimization by selecting appropriate instance sizes for the build workload
5. THE module SHALL configure the pipeline build timeout to 60 minutes maximum via the `image_tests_configuration` timeout setting, preventing runaway builds from accumulating cost
6. THE module SHALL configure `terminate_instance_on_failure = true` in the Infrastructure_Configuration to ensure failed build instances are cleaned up immediately

### Requirement 9: Observability and Notifications

**User Story:** As a platform operator, I want visibility into pipeline execution status and failures, so that I can respond to build issues and track pipeline health.

#### Acceptance Criteria

1. THE module SHALL create a CloudWatch Log Group at `/devbox/image-builder/builds` with a configurable retention period (default 30 days) and reference it in the Infrastructure_Configuration for build log collection
2. THE module SHALL create an SNS topic for pipeline notifications and configure an EventBridge rule to publish events when pipeline execution enters `FAILED`, `CANCELLED`, or `AVAILABLE` states
3. THE module SHALL accept an optional list of email endpoints to subscribe to the SNS topic for failure alerts
4. THE module SHALL output the SNS topic ARN and CloudWatch Log Group name as Terraform outputs for integration with external monitoring
5. WHEN a pipeline execution fails, THE EventBridge rule SHALL include the pipeline ARN, execution ID, and failure reason in the SNS notification message detail

### Requirement 10: Environment Integration

**User Story:** As a platform operator, I want the Image Builder module integrated into the existing environment configuration pattern, so that it follows the same conventions as the VPC and egress modules.

#### Acceptance Criteria

1. THE environment configuration (`environments/dev/main.tf`) SHALL instantiate the Image Builder module with references to `module.egress.vpc_id`, `module.egress.private_subnets`, and appropriate local values
2. THE module SHALL be placed at path `modules/image-builder/` following the existing repository directory structure convention
3. THE module SHALL accept a `tags` variable of type `map(string)` that is merged with module-internal tags on all created resources, consistent with the tagging pattern used by the VPC and egress modules
4. THE environment configuration SHALL pass `local.environment` and `local.tags` to the module, and the module SHALL use these to construct resource names with the pattern `devbox-{environment}-image-builder-{resource}`
5. THE module SHALL declare provider version constraints in a `versions.tf` file requiring `hashicorp/aws >= 6.0` and `terraform >= 1.0`, matching the existing environment constraints
6. THE module outputs SHALL be re-exported from the environment `outputs.tf` file, including the pipeline ARN, SSM parameter path, and SNS topic ARN
