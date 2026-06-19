variable "name" {
  description = "Name prefix for peering resources"
  type        = string
}

variable "requester_vpc_id" {
  description = "VPC ID of the requester (workload VPC)"
  type        = string
}

variable "requester_cidr_block" {
  description = "CIDR block of the requester VPC"
  type        = string
}

variable "requester_ipv6_cidr_block" {
  description = "IPv6 CIDR block of the requester VPC (used for return routes)"
  type        = string
  default     = ""
}

variable "requester_route_table_ids" {
  description = "Route table IDs in the requester VPC to add peering routes"
  type        = list(string)
}

variable "accepter_vpc_id" {
  description = "VPC ID of the accepter (egress VPC)"
  type        = string
}

variable "accepter_cidr_block" {
  description = "CIDR block of the accepter VPC"
  type        = string
}

variable "accepter_ipv6_cidr_block" {
  description = "IPv6 CIDR block of the accepter VPC"
  type        = string
  default     = ""
}

variable "accepter_route_table_ids" {
  description = "Route table IDs in the accepter VPC to add peering routes"
  type        = list(string)
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "enable_ipv6" {
  description = "Whether to create IPv6 peering routes"
  type        = bool
  default     = true
}
