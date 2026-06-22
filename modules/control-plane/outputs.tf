output "nlb_dns_name" {
  description = "Public DNS name of the control-plane NLB (the Route 53 alias for domain_name points here)"
  value       = aws_lb.this.dns_name
}

output "nlb_eip" {
  description = "Static Elastic IP fronting the control-plane NLB"
  value       = aws_eip.nlb.public_ip
}

output "control_plane_url" {
  description = "Public URL of the control plane (point the CLI --server-url and dashboard here)"
  value       = "https://${var.domain_name}"
}

output "ecr_repository_url" {
  description = "ECR repository CI pushes the devbox-server image to"
  value       = aws_ecr_repository.server.repository_url
}

output "ecr_repository_name" {
  description = "ECR repository name (for the deploy workflow)"
  value       = aws_ecr_repository.server.name
}

output "github_deploy_role_arn" {
  description = "ARN of the role GitHub Actions assumes to push images and deploy (set as the workflow's role-to-assume)"
  value       = local.create_github_deploy ? aws_iam_role.github_deploy[0].arn : null
}

output "dsql_cluster_identifier" {
  description = "Aurora DSQL cluster identifier"
  value       = aws_dsql_cluster.this.identifier
}

output "dsql_endpoint" {
  description = "Aurora DSQL connection endpoint"
  value       = local.dsql_endpoint
}

output "dsql_bootstrap_sql" {
  description = "One-time bootstrap SQL for the DSQL cluster: run as the admin role to create the app database role, map it to the task IAM role, and give it an owned schema. Apply before the service connects."
  value = templatefile("${path.module}/templates/bootstrap.sql.tftpl", {
    db_role       = local.db_role
    task_role_arn = aws_iam_role.task.arn
  })
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.this.name
}

output "service_name" {
  description = "ECS service name"
  value       = aws_ecs_service.server.name
}

output "ecs_task_family" {
  description = "ECS task-definition family (for the deploy workflow's ECS_TASK_FAMILY)"
  value       = aws_ecs_task_definition.server.family
}

output "task_role_arn" {
  description = "ARN of the control-plane task (runtime) role"
  value       = aws_iam_role.task.arn
}
