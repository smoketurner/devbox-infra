output "vpc_id" {
  description = "The ID of the egress VPC"
  value       = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  description = "The CIDR block of the egress VPC"
  value       = module.vpc.vpc_cidr_block
}

output "vpc_ipv6_cidr_block" {
  description = "The IPv6 CIDR block of the egress VPC"
  value       = module.vpc.vpc_ipv6_cidr_block
}

output "private_subnets" {
  description = "List of IDs of private subnets"
  value       = module.vpc.private_subnets
}

output "public_subnets" {
  description = "List of IDs of public subnets"
  value       = module.vpc.public_subnets
}

output "nat_public_ips" {
  description = "List of public Elastic IPs created for NAT gateways"
  value       = module.vpc.nat_public_ips
}

output "azs" {
  description = "List of availability zones used"
  value       = module.vpc.azs
}
