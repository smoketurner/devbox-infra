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

output "image_builder_pipeline_arn" {
  description = "ARN of the Image Builder pipeline"
  value       = module.image_builder.pipeline_arn
}

output "image_builder_ssm_parameter_name" {
  description = "Name of the SSM parameter storing the latest AMI ID"
  value       = module.image_builder.ssm_parameter_name
}

output "image_builder_sns_topic_arn" {
  description = "ARN of the pipeline notification SNS topic"
  value       = module.image_builder.sns_topic_arn
}

output "route53_name_servers" {
  description = "Name servers for the devbox.farm hosted zone (set these as NS records at the registrar)"
  value       = aws_route53_zone.devbox_farm.name_servers
}

output "control_plane_url" {
  description = "Public URL of the control plane (CLI --server-url and dashboard)"
  value       = module.control_plane.control_plane_url
}
