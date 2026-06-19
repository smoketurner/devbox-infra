variable "name" {
  description = "Name of the egress VPC"
  type        = string
}

variable "cidr" {
  description = "CIDR block for the egress VPC"
  type        = string
}

variable "azs" {
  description = "List of availability zones"
  type        = list(string)
}

variable "private_subnets" {
  description = "List of private subnet CIDR blocks (for NAT gateway and proxy)"
  type        = list(string)
  default     = []
}

variable "public_subnets" {
  description = "List of public subnet CIDR blocks (internet-facing)"
  type        = list(string)
  default     = []
}

variable "single_nat_gateway" {
  description = "Use a single NAT gateway for all private subnets"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "associated_vpc_ids" {
  description = "VPC IDs to associate with private hosted zones for VPC endpoint DNS resolution"
  type        = list(string)
  default     = []
}

variable "associated_vpc_cidrs" {
  description = "CIDR blocks of peered VPCs to allow HTTPS access to VPC endpoints"
  type        = list(string)
  default     = []
}
