variable "name_prefix" {
  description = "Prefix for resource names (e.g., devbox-dev)"
  type        = string
}

variable "build_vpc_id" {
  description = "VPC ID where the short-lived builder instance runs"
  type        = string
}

variable "build_subnet_ids" {
  description = "Private subnet IDs for the builder (must have NAT egress to GitHub and the AWS APIs)"
  type        = list(string)

  validation {
    condition     = length(var.build_subnet_ids) > 0
    error_message = "At least one build subnet ID must be provided."
  }
}

variable "builder_instance_type" {
  description = "Instance type for the snapshot builder (arm64/Graviton, to match the pool toolchain)"
  type        = string
  default     = "m7g.large"
}

variable "ami_parameter" {
  description = "SSM parameter the builder launches from, so the snapshot is built against the same toolchain as the pool (R10). Resolved to a concrete AMI id at run time."
  type        = string
  default     = "/devbox/ami/latest"

  validation {
    condition     = startswith(var.ami_parameter, "/")
    error_message = "SSM parameter path must start with /."
  }
}

variable "ssm_parameter_path" {
  description = "SSM Parameter Store path the pipeline publishes the latest workspace snapshot id to. The automation is granted ssm:PutParameter on exactly this path."
  type        = string
  default     = "/devbox/workspace-snapshot/latest"

  validation {
    condition     = startswith(var.ssm_parameter_path, "/")
    error_message = "SSM parameter path must start with /."
  }
}

variable "repos" {
  description = "Git repositories to seed into the workspace snapshot, as clone URLs (e.g. https://github.com/smoketurner/devbox.git). Cloned source-only into /workspace/<name>."
  type        = list(string)

  validation {
    condition     = length(var.repos) > 0
    error_message = "At least one repository must be provided."
  }
}

variable "data_volume_size_gb" {
  description = "Size of the workspace data volume the builder formats and snapshots, in GB"
  type        = number
  default     = 50

  validation {
    condition     = var.data_volume_size_gb > 0
    error_message = "Data volume size must be greater than 0."
  }
}

variable "schedule_expression" {
  description = "EventBridge schedule expression for the snapshot build cadence"
  type        = string
  default     = "rate(30 minutes)"
}

variable "schedule_enabled" {
  description = "Whether the scheduled snapshot build is active"
  type        = bool
  default     = true
}

variable "retention_count" {
  description = "Number of most-recent workspace snapshots to retain; older untagged snapshots are deleted each run"
  type        = number
  default     = 5

  validation {
    condition     = var.retention_count >= 1
    error_message = "Retention count must be at least 1."
  }
}

variable "clone_warm_timeout_seconds" {
  description = "Hard timeout for the clone/warm run command on the builder, in seconds"
  type        = number
  default     = 3600

  validation {
    condition     = var.clone_warm_timeout_seconds >= 60
    error_message = "Clone/warm timeout must be at least 60 seconds."
  }
}

variable "ami_kms_key_arn" {
  description = "ARN of the KMS key the golden AMI's root snapshot is encrypted with (image-builder's CMK). The automation role calls RunInstances directly, so it must be able to use this key to launch the builder from the AMI; granted via IAM relying on the key's root-account delegation, which avoids a module cycle."
  type        = string
}

variable "github_app_private_key_param_arn" {
  description = "ARN of the SSM SecureString parameter holding the GitHub App private key (PEM). The builder reads it to mint a read-only installation token for cloning."
  type        = string
}

variable "github_app_private_key_param_name" {
  description = "Name of the SSM SecureString parameter holding the GitHub App private key (PEM). Passed to the clone/warm script for `aws ssm get-parameter`."
  type        = string
}

variable "github_app_id" {
  description = "GitHub App ID (or Client ID) used as the JWT issuer when minting the installation token. Empty disables authenticated cloning (public repos only)."
  type        = string
  default     = ""
}

variable "github_app_installation_id" {
  description = "GitHub App installation ID to mint the token against. Empty disables authenticated cloning."
  type        = string
  default     = ""
}

variable "log_retention_days" {
  description = "CloudWatch log group retention period in days for builder run-command output"
  type        = number
  default     = 30

  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653
    ], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch retention value."
  }
}

variable "trusted_account_ids" {
  description = "AWS account IDs allowed to use the workspace snapshot CMK (cross-account snapshot sharing)"
  type        = list(string)
  default     = []
}

variable "notification_emails" {
  description = "Email addresses to subscribe to snapshot-build failure notifications"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
