# Implementation Plan: AMI Image Builder

## Overview

Implement the `modules/image-builder/` Terraform module that provisions an EC2 Image Builder pipeline for producing golden AMIs. The module creates IAM roles, networking, AWSTOE components, the pipeline with recipe/infrastructure/distribution configurations, SSM parameter publication, lifecycle policy, and notifications. The environment integration wires it into `environments/dev/main.tf`.

## Tasks

- [x] 1. Set up module scaffold and core declarations
  - [x] 1.1 Create module directory structure and versions.tf
    - Create `modules/image-builder/` directory
    - Create `versions.tf` with `terraform >= 1.0` and `hashicorp/aws >= 6.0` constraints matching the egress module pattern
    - _Requirements: 10.2, 10.5_

  - [x] 1.2 Create variables.tf with all input variable declarations
    - Declare all variables from the design: `name_prefix`, `environment`, `egress_vpc_id`, `egress_subnet_ids`, `build_instance_type`, `schedule_expression`, `schedule_enabled`, `pipeline_execution_start_condition`, `image_tests_timeout_minutes`, `log_retention_days`, `ami_name_pattern`, `ssm_parameter_path`, `trusted_account_ids`, `distribution_regions`, `notification_emails`, `s3_bucket_arn`, `secrets_arns`, `component_files`, `tags`
    - Add validation blocks (e.g., `ssm_parameter_path` must start with `/`)
    - Set defaults per the design: `m5.large`, `cron(0 2 ? * SUN *)`, 30 days retention, etc.
    - _Requirements: 1.1, 1.4, 2.4, 3.4, 3.7, 4.1, 4.3, 4.4, 5.1, 6.1, 6.2, 8.4, 10.3_

  - [x] 1.3 Create locals.tf with computed values and tag merging
    - Define `local.tags` that merges `var.tags` with module-internal tags (`Pipeline = "ami-image-builder"`, `Environment = var.environment`, `ManagedBy = "terraform"`)
    - Define name construction pattern: `${var.name_prefix}-image-builder-{resource}`
    - _Requirements: 10.3, 10.4_

  - [x] 1.4 Create outputs.tf with all module outputs
    - Output `pipeline_arn`, `distribution_configuration_arn`, `ssm_parameter_name`, `ssm_parameter_arn`, `sns_topic_arn`, `cloudwatch_log_group_name`, `build_security_group_id`, `build_instance_role_arn`
    - _Requirements: 4.5, 5.4, 9.4_

- [x] 2. Implement IAM roles and instance profile
  - [x] 2.1 Create iam.tf with build instance role and instance profile
    - Create `aws_iam_role` with `ec2.amazonaws.com` trust policy
    - Attach managed policies: `EC2InstanceProfileForImageBuilder`, `AmazonSSMManagedInstanceCore`
    - Create custom inline policy for `s3:GetObject` on `var.s3_bucket_arn`
    - Conditionally add `secretsmanager:GetSecretValue` for `var.secrets_arns` when non-empty
    - Create `aws_iam_instance_profile` wrapping the role
    - Ensure role has NO permissions to modify IAM or access production databases
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7_

  - [x] 2.2 Add lifecycle policy execution role to iam.tf
    - Create `aws_iam_role` for lifecycle with `imagebuilder.amazonaws.com` trust
    - Add inline policy: `ec2:DeregisterImage`, `ec2:DescribeImages`, `ec2:DeleteSnapshot`, `ec2:DescribeSnapshots`, `imagebuilder:GetImage`, `imagebuilder:ListImages`, `tag:GetResources`
    - _Requirements: 8.1_

  - [x] 2.3 Add SSM parameter write permission to build instance role
    - Grant `ssm:PutParameter` on the SSM parameter ARN for native distribution
    - _Requirements: 5.3_

- [x] 3. Implement networking configuration
  - [x] 3.1 Create networking.tf with build instance security group
    - Create `aws_security_group` in `var.egress_vpc_id`
    - Add egress rule: all traffic to `0.0.0.0/0` and `::/0`
    - Add self-referencing ingress rule for multi-instance test scenarios
    - No external inbound rules
    - _Requirements: 2.1, 2.2, 2.3, 2.4_

- [x] 4. Checkpoint - Validate foundation
  - Ensure all tests pass, ask the user if questions arise.
  - Run `terraform validate` and `terraform fmt -check` on the module directory.

- [x] 5. Implement AWSTOE components
  - [x] 5.1 Create component YAML stub files in modules/image-builder/components/
    - Create placeholder YAML documents for all 10 components: `01-base-updates.yml`, `02-dev-tools.yml`, `03-language-runtimes.yml`, `04-container-tooling.yml`, `05-agent-dependencies.yml`, `06-repo-cloning.yml`, `07-warmup-daemon.yml`, `08-ssh-config.yml`, `09-security-hardening.yml`, `99-validation.yml`
    - Each must be valid AWSTOE YAML with `name`, `description`, `schemaVersion`, and `phases` (build/validate)
    - The validation component (99) should verify installed tools and service status
    - _Requirements: 7.1, 7.2, 7.5_

  - [x] 5.2 Create components.tf with aws_imagebuilder_component resources
    - Use `for_each` on `var.component_files` map
    - Use `templatefile()` for variable interpolation in YAML documents
    - Implement content-hash naming: include `substr(sha256(...), 0, 8)` in resource name for immutability
    - Set `platform = "Linux"` and version from `each.value.version`
    - Tag with `ComponentOrder` for operational clarity
    - _Requirements: 7.1, 7.3, 7.4, 7.6_

- [x] 6. Implement pipeline, recipe, and distribution
  - [x] 6.1 Create main.tf with image recipe
    - Create `aws_imagebuilder_image_recipe` referencing the AL2023 kernel 6.18 parent image via SSM parameter `/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.18-x86_64`
    - Add `data` source for the SSM parameter to resolve the base AMI
    - Attach components in order from `var.component_files`
    - Configure EBS block device with encryption using `aws/ebs` KMS key
    - _Requirements: 1.2, 1.3, 4.4_

  - [x] 6.2 Add infrastructure configuration to main.tf
    - Create `aws_imagebuilder_infrastructure_configuration` referencing the instance profile, security group, subnet, and CloudWatch log group
    - Set `instance_types`, `terminate_instance_on_failure = true`
    - Configure `instance_metadata_options` with `http_tokens = "required"` for IMDSv2
    - _Requirements: 1.4, 2.1, 2.5, 8.6_

  - [x] 6.3 Add distribution configuration to main.tf
    - Create `aws_imagebuilder_distribution_configuration` for `us-east-1`
    - Configure `ami_distribution_configuration` with name pattern, tags, KMS key, and launch permissions
    - Add `ssm_parameter_configuration` block for native AMI ID publication
    - Conditionally add cross-account sharing via `trusted_account_ids`
    - Conditionally add cross-region distribution via `distribution_regions`
    - _Requirements: 1.5, 4.1, 4.2, 4.3, 4.4, 5.1_

  - [x] 6.4 Add pipeline resource to main.tf
    - Create `aws_imagebuilder_pipeline` referencing recipe, infrastructure config, and distribution config
    - Configure `schedule` with `schedule_expression` and `pipeline_execution_start_condition`
    - Set `enhanced_image_metadata_enabled = true`
    - Configure `image_tests_configuration` with `image_tests_enabled = true` and timeout
    - Conditionally enable/disable schedule via `var.schedule_enabled`
    - _Requirements: 1.1, 6.1, 6.2, 6.3, 6.5, 8.5_

- [x] 7. Implement SSM parameter resource
  - [x] 7.1 Add SSM parameter to main.tf
    - Create `aws_ssm_parameter` at `var.ssm_parameter_path` with type `String` and data type `aws:ec2:image`
    - Set initial value to the resolved base AMI ID (from data source)
    - Add `lifecycle { ignore_changes = [value] }` so Terraform doesn't revert pipeline-written values
    - Tag with Environment, ManagedBy, Pipeline
    - _Requirements: 5.1, 5.2, 5.4, 5.5_

- [x] 8. Implement lifecycle policy
  - [x] 8.1 Add lifecycle policy to main.tf
    - Create `aws_imagebuilder_lifecycle_policy` with `resource_type = "AMI_IMAGE"`
    - Configure `policy_detail` with DELETE action (amis + snapshots), COUNT filter retaining 5
    - Add `exclusion_rules` for tags `devbox:status = "production"` and `devbox:keep = "true"`
    - Reference the lifecycle execution role
    - Configure `resource_selection` using the recipe name and version
    - _Requirements: 8.1, 8.2, 8.3_

- [x] 9. Checkpoint - Validate core module
  - Ensure all tests pass, ask the user if questions arise.
  - Run `terraform validate` and `terraform fmt -check` on the module directory.

- [x] 10. Implement notifications and observability
  - [x] 10.1 Create notifications.tf with CloudWatch log group, SNS topic, and EventBridge rule
    - Create `aws_cloudwatch_log_group` at `/devbox/image-builder/builds` with configurable retention
    - Create `aws_sns_topic` for pipeline notifications
    - Conditionally create `aws_sns_topic_subscription` for each email in `var.notification_emails`
    - Create `aws_cloudwatch_event_rule` matching FAILED, CANCELLED, AVAILABLE states for the pipeline ARN
    - Create `aws_cloudwatch_event_target` routing to the SNS topic
    - Add SNS topic policy allowing EventBridge to publish
    - _Requirements: 9.1, 9.2, 9.3, 9.4, 9.5_

- [x] 11. Implement environment integration
  - [x] 11.1 Add image_builder module call to environments/dev/main.tf
    - Add `module "image_builder"` block referencing `../../modules/image-builder`
    - Pass `name_prefix = "devbox-${local.environment}"`, `environment = local.environment`
    - Pass `egress_vpc_id = module.egress.vpc_id`, `egress_subnet_ids = module.egress.private_subnets`
    - Pass `tags = local.tags`
    - Configure `component_files` map with all 10 component file paths and versions
    - _Requirements: 10.1, 10.4_

  - [x] 11.2 Add module outputs to environments/dev/outputs.tf
    - Re-export `module.image_builder.pipeline_arn`, `module.image_builder.ssm_parameter_name`, `module.image_builder.sns_topic_arn`
    - _Requirements: 10.6_

- [x] 12. Final checkpoint - Full validation
  - Ensure all tests pass, ask the user if questions arise.
  - Run `terraform fmt -check -recursive` from repository root.
  - Run `terraform validate` in `environments/dev/` directory.
  - Run `terraform plan -target=module.image_builder` in `environments/dev/` to verify no errors.

## Notes

- No property-based tests apply — this is declarative IaC with no pure business logic functions
- Validation uses `terraform validate`, `terraform fmt -check`, and `terraform plan`
- Component YAML files are stubs containing valid AWSTOE structure; actual provisioning content is implementation detail
- The lifecycle `ignore_changes = [value]` on SSM parameter is critical to avoid reverting pipeline-written AMI IDs
- Tasks reference specific sub-requirements for traceability
- Checkpoints ensure incremental validation at module-foundation and full-module stages

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1", "1.2", "1.3", "1.4"] },
    { "id": 1, "tasks": ["2.1", "3.1", "5.1"] },
    { "id": 2, "tasks": ["2.2", "2.3", "5.2"] },
    { "id": 3, "tasks": ["6.1", "10.1"] },
    { "id": 4, "tasks": ["6.2", "6.3", "7.1"] },
    { "id": 5, "tasks": ["6.4", "8.1"] },
    { "id": 6, "tasks": ["11.1"] },
    { "id": 7, "tasks": ["11.2"] }
  ]
}
```
