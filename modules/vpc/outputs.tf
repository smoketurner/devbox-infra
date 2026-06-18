output "vpc_id" {
  description = "The ID of the VPC"
  value       = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  description = "The CIDR block of the VPC"
  value       = module.vpc.vpc_cidr_block
}

output "vpc_ipv6_cidr_block" {
  description = "The IPv6 CIDR block of the VPC"
  value       = module.vpc.vpc_ipv6_cidr_block
}

output "private_subnets" {
  description = "List of IDs of private subnets"
  value       = module.vpc.private_subnets
}

output "private_subnet_cidr_blocks" {
  description = "List of CIDR blocks of private subnets"
  value       = module.vpc.private_subnets_cidr_blocks
}

output "private_subnet_ipv6_cidr_blocks" {
  description = "List of IPv6 CIDR blocks of private subnets"
  value       = module.vpc.private_subnet_ipv6_cidr_blocks
}

output "azs" {
  description = "List of availability zones used"
  value       = module.vpc.azs
}

output "vpc_endpoint_security_group_id" {
  description = "ID of the security group attached to VPC endpoints"
  value       = aws_security_group.vpc_endpoints.id
}
