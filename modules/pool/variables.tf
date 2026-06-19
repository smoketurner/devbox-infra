variable "name_prefix" {
  description = "Prefix for resource names (e.g., devbox-dev)"
  type        = string
}

variable "environment" {
  description = "Environment name (e.g., dev)"
  type        = string
}

variable "pool_id" {
  description = "Pool identifier used in naming contract (ASG = devbox-pool-<pool_id>, hook = devbox-warmup-<pool_id>)"
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

variable "warmup_heartbeat_timeout" {
  description = "Lifecycle hook heartbeat timeout in seconds"
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

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
