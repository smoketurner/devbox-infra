variable "name_prefix" {
  description = "Prefix for resource names (e.g., devbox-dev)"
  type        = string
}

variable "environment" {
  description = "Environment name (e.g., dev)"
  type        = string
}

variable "pool_id" {
  description = "Pool identifier used in naming contract (ASG = devbox-pool-<pool_id>)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where instances run"
  type        = string
}

variable "subnet_ids" {
  description = "Private subnet IDs for ASG"
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) > 0
    error_message = "At least one subnet ID must be provided."
  }
}

variable "instance_type" {
  description = "EC2 instance type (arm64/Graviton)"
  type        = string
  default     = "m7g.large"
}

variable "min_size" {
  description = "ASG minimum size"
  type        = number
  default     = 0
}

variable "max_size" {
  description = "ASG maximum size"
  type        = number
  default     = 10
}

variable "health_check_type" {
  description = "ASG health check type"
  type        = string
  default     = "EC2"
}

variable "health_check_grace_period" {
  description = "Health check grace period in seconds"
  type        = number
  default     = 300
}

variable "security_group_ids" {
  description = "Security group IDs for instances"
  type        = list(string)
}

variable "ssm_ami_parameter" {
  description = "SSM parameter path for AMI ID resolution"
  type        = string
  default     = "/devbox/ami/latest"

  validation {
    condition     = startswith(var.ssm_ami_parameter, "/")
    error_message = "SSM parameter path must start with /."
  }
}

variable "ebs_volume_size" {
  description = "EBS volume size in GB"
  type        = number
  default     = 30

  validation {
    condition     = var.ebs_volume_size > 0
    error_message = "EBS volume size must be greater than 0."
  }
}

variable "ebs_encrypted" {
  description = "Whether EBS volumes are encrypted"
  type        = bool
  default     = true
}

variable "metadata_hop_limit" {
  description = "IMDSv2 hop limit"
  type        = number
  default     = 2
}

variable "ami_refresh_min_healthy_percentage" {
  description = "Minimum healthy percentage during an AMI-refresh instance refresh. Kept at 50 so small warm pools roll one host at a time without deadlocking (90% can't replace any instance on a 2-host ASG) or fully draining."
  type        = number
  default     = 50

  validation {
    condition     = var.ami_refresh_min_healthy_percentage >= 0 && var.ami_refresh_min_healthy_percentage <= 100
    error_message = "ami_refresh_min_healthy_percentage must be between 0 and 100."
  }
}

variable "ami_refresh_instance_warmup" {
  description = "Seconds the ASG waits after a replacement reaches InService before refreshing the next batch. With no launch lifecycle hook, InService no longer implies the host is warmed (the control plane gates readiness on the devbox:ready tag), so 0 rolls batches as soon as replacements are InService — not warm. Raise it to give replacements time to warm between batches."
  type        = number
  default     = 0

  validation {
    condition     = var.ami_refresh_instance_warmup >= 0
    error_message = "ami_refresh_instance_warmup must be non-negative."
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
