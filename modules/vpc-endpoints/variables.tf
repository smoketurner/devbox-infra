variable "name_prefix" {
  description = "Prefix for resource names (e.g., devbox-dev)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where the interface and gateway endpoints are created"
  type        = string
}

variable "vpc_cidr_block" {
  description = "IPv4 CIDR of the VPC, used for the endpoint SG ingress from in-VPC clients (pool nodes)"
  type        = string
}

variable "vpc_ipv6_cidr_block" {
  description = "IPv6 CIDR of the VPC, used for the endpoint SG ingress from in-VPC clients (dual-stack parity)"
  type        = string
}

variable "subnet_ids" {
  description = "Private subnet IDs the interface endpoints' ENIs are placed in"
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) > 0
    error_message = "At least one subnet ID must be provided."
  }
}

variable "private_route_table_ids" {
  description = "Private route table IDs associated with the S3 gateway endpoint"
  type        = list(string)
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
