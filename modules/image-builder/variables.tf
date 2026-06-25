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
  default     = 30

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
  description = "URL to download the prebuilt devbox-agent binary baked into the AMI (arm64 musl static)"
  type        = string
  default     = "https://github.com/smoketurner/devbox/releases/latest/download/devbox-agent-aarch64-unknown-linux-musl"
}

variable "devbox_agent_sha256" {
  description = "Optional sha256 checksum of the devbox-agent binary to pin (empty skips verification)"
  type        = string
  default     = ""
}

# Workspace-freshen config baked into the warmup service's EnvironmentFile
# (/etc/devbox/warmup.env). The warmup systemd unit does not read /etc/environment,
# so the agent's DEVBOX_GITHUB_* config must reach it here. All non-secret; the App
# private key itself is read from SSM at warmup via the host instance profile.

variable "github_app_id" {
  description = "GitHub App ID / Client ID the warming agent uses as the JWT issuer. Empty disables authenticated fetch (public repos only)."
  type        = string
  default     = ""
}

variable "github_app_key_param" {
  description = "Name of the SSM SecureString parameter holding the GitHub App private key, read on-box by the warming agent (DEVBOX_GITHUB_KEY_PARAM)."
  type        = string
  default     = ""
}

variable "docker_images" {
  description = "Container images pre-pulled into the AMI's /var/lib/docker at build time so first container use is warm. Refreshed on AMI rebuild."
  type        = list(string)
  default     = []
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
