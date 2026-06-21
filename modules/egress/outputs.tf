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

output "nat_eni_id" {
  description = "ID of the fck-nat instance's network interface"
  value       = module.fck_nat.eni_id
}

output "nat_security_group_id" {
  description = "ID of the security group attached to the fck-nat instance"
  value       = aws_security_group.fck_nat.id
}

output "azs" {
  description = "List of availability zones used"
  value       = module.vpc.azs
}

output "private_route_table_ids" {
  description = "List of IDs of private route tables"
  value       = module.vpc.private_route_table_ids
}
