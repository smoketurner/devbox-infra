output "vpc_id" {
  description = "The ID of the workload VPC"
  value       = module.vpc.vpc_id
}

output "private_subnets" {
  description = "List of private subnet IDs in the workload VPC"
  value       = module.vpc.private_subnets
}

output "nat_eni_id" {
  description = "Network interface ID of the fck-nat instance providing workload egress"
  value       = module.vpc.nat_eni_id
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

output "github_deploy_role_arn" {
  description = "ARN of the role GitHub Actions assumes to push images and deploy (set as the workflow's role-to-assume)"
  value       = module.control_plane.github_deploy_role_arn
}

output "dsql_bootstrap_sql" {
  description = "One-time bootstrap SQL for the DSQL cluster (run as admin before first deploy to create the app database role and its owned schema)"
  value       = module.control_plane.dsql_bootstrap_sql
}

output "ecr_repository_url" {
  description = "ECR repository CI pushes the devbox-server image to"
  value       = module.control_plane.ecr_repository_url
}

output "ecr_repository_name" {
  description = "ECR repository name (for the deploy workflow)"
  value       = module.control_plane.ecr_repository_name
}

output "ecs_cluster_name" {
  description = "ECS cluster name (for the deploy workflow)"
  value       = module.control_plane.ecs_cluster_name
}

output "service_name" {
  description = "ECS service name (for the deploy workflow)"
  value       = module.control_plane.service_name
}

output "ecs_task_family" {
  description = "ECS task-definition family (for the deploy workflow's ECS_TASK_FAMILY)"
  value       = module.control_plane.ecs_task_family
}
