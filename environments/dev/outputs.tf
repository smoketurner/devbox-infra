output "vpc_id" {
  description = "The ID of the workload VPC"
  value       = module.vpc.vpc_id
}

output "private_subnets" {
  description = "List of private subnet IDs in the workload VPC"
  value       = module.vpc.private_subnets
}

output "egress_vpc_id" {
  description = "The ID of the egress VPC"
  value       = module.egress.vpc_id
}

output "egress_nat_public_ips" {
  description = "Public IPs of the NAT gateways in the egress VPC"
  value       = module.egress.nat_public_ips
}
