variable "name_prefix" {
  description = "Prefix for resource names (e.g., devbox-dev)"
  type        = string
}

variable "build_vpc_id" {
  description = "VPC ID where build instances run"
  type        = string
}

variable "build_subnet_ids" {
  description = "Private subnet IDs for build instances (must have NAT egress for package downloads)"
  type        = list(string)

  validation {
    condition     = length(var.build_subnet_ids) > 0
    error_message = "At least one build subnet ID must be provided."
  }
}

variable "build_instance_type" {
  description = "Instance type for Image Builder build instances (arm64/Graviton)"
  type        = string
  default     = "m7g.large"
}

variable "schedule_expression" {
  description = "Cron schedule expression for pipeline execution"
  type        = string
  default     = "cron(0 2 ? * SUN *)"
}

variable "schedule_enabled" {
  description = "Whether automatic pipeline scheduling is active"
  type        = bool
  default     = true
}

variable "pipeline_execution_start_condition" {
  description = "Condition for starting pipeline execution"
  type        = string
  default     = "EXPRESSION_MATCH_AND_DEPENDENCY_UPDATES_AVAILABLE"

  validation {
    condition = contains([
      "EXPRESSION_MATCH_AND_DEPENDENCY_UPDATES_AVAILABLE",
      "EXPRESSION_MATCH_ONLY"
    ], var.pipeline_execution_start_condition)
    error_message = "Must be EXPRESSION_MATCH_AND_DEPENDENCY_UPDATES_AVAILABLE or EXPRESSION_MATCH_ONLY."
  }
}

variable "image_tests_timeout_minutes" {
  description = "Timeout in minutes for image validation tests"
  type        = number
  default     = 60

  validation {
    condition     = var.image_tests_timeout_minutes >= 1 && var.image_tests_timeout_minutes <= 1440
    error_message = "Image tests timeout must be between 1 and 1440 minutes."
  }
}

variable "log_retention_days" {
  description = "CloudWatch log group retention period in days"
  type        = number
  default     = 7

  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653
    ], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch retention value."
  }
}

variable "ami_name_pattern" {
  description = "Name pattern for the output AMI including Image Builder expression variables"
  type        = string
  default     = "devbox-golden-{{imagebuilder:buildDate}}"
}

variable "ssm_parameter_path" {
  description = "SSM Parameter Store path for publishing the latest AMI ID. The pipeline execution role is granted ssm:PutParameter on exactly this path."
  type        = string
  default     = "/devbox/ami/latest"

  validation {
    condition     = startswith(var.ssm_parameter_path, "/")
    error_message = "SSM parameter path must start with /."
  }
}

variable "trusted_account_ids" {
  description = "AWS account IDs allowed to use the output AMI for cross-account sharing"
  type        = list(string)
  default     = []
}

variable "distribution_regions" {
  description = "Additional AWS regions to copy the output AMI to"
  type        = list(string)
  default     = []
}

variable "notification_emails" {
  description = "Email addresses to subscribe to pipeline failure notifications"
  type        = list(string)
  default     = []
}

variable "s3_bucket_arn" {
  description = "S3 bucket ARN for component artifacts and build manifests"
  type        = string
  default     = ""
}

variable "secrets_arns" {
  description = "Secrets Manager ARNs for private Git repository access tokens"
  type        = list(string)
  default     = []
}

variable "component_files" {
  description = "List of component YAML filenames (order derived from filename prefix)"
  type        = list(string)
}

variable "devbox_agent_url" {
  description = "URL to download the prebuilt devbox-agent binary baked into the AMI (arm64 musl static). A releases/latest URL is resolved to its concrete release tag at build time; the binary is always verified against that release's SHA256SUMS. A versioned releases/download/<tag>/ URL pins the version."
  type        = string
  default     = "https://github.com/smoketurner/devbox/releases/latest/download/devbox-agent-aarch64-unknown-linux-musl"
}

# Control-plane URL for the warming agent. Baked into the warmup service's
# EnvironmentFile (/etc/devbox/warmup.env) because the systemd unit does not read
# /etc/environment, and also appended to /etc/environment so on-claim
# `devbox-agent checkout` (which runs outside that unit) requests tokens too. All
# non-secret; the agent authenticates to the control plane with this instance's
# AWS identity and the App private key never lives on the box.

variable "control_plane_url" {
  description = "Control-plane base URL (DEVBOX_SERVER_URL) the warming agent requests repo-scoped GitHub tokens from. Empty disables authenticated fetch (public repos only)."
  type        = string
  default     = ""
}

variable "egress_proxy_url" {
  description = "HTTP(S)_PROXY value baked onto the box (e.g. http://host:3128). Empty leaves egress unproxied."
  type        = string
  default     = ""
}

variable "egress_no_proxy" {
  description = "NO_PROXY value baked onto the box (control-plane host, IMDS, .amazonaws.com, localhost)."
  type        = string
  default     = ""
}

variable "docker_images" {
  description = "Container images pre-pulled into the AMI's /var/lib/docker at build time so first container use is warm. Refreshed on AMI rebuild."
  type        = list(string)
  default     = []
}

# Test-stage workspace-mount exercise. The 04-devbox test phase (test stage, on a
# fresh instance launched from the new AMI) resolves the workspace snapshot,
# attaches it as a real volume, mounts it, and asserts devbox-warmup reaches active.

variable "workspace_snapshot_param" {
  description = "Name of the SSM parameter holding the latest workspace snapshot id, resolved in the test stage to attach the real /workspace volume. Passed by name (not a snapshot-builder module reference) to avoid a dependency cycle."
  type        = string
  default     = "/devbox/workspace-snapshot/latest"

  validation {
    condition     = startswith(var.workspace_snapshot_param, "/")
    error_message = "Workspace snapshot parameter name must start with /."
  }
}

variable "warmup_fetch_timeout_secs" {
  description = "Optional override for the agent's overall fetch budget (WARMUP_FETCH_TIMEOUT_SECS). Empty uses the agent default (120s)."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
