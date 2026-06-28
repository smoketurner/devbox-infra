output "ssm_parameter_name" {
  description = "Name of the SSM parameter storing the latest workspace snapshot id (the pool consumes this for ordering and resolution)"
  value       = aws_ssm_parameter.workspace_snapshot.name
}

output "ssm_parameter_arn" {
  description = "ARN of the SSM parameter storing the latest workspace snapshot id"
  value       = aws_ssm_parameter.workspace_snapshot.arn
}

output "automation_document_name" {
  description = "Name of the SSM Automation document that builds the snapshot"
  value       = aws_ssm_document.snapshot_build.name
}

output "automation_role_arn" {
  description = "ARN of the SSM Automation execution role"
  value       = aws_iam_role.snapshot_automation.arn
}

output "builder_instance_role_arn" {
  description = "ARN of the builder instance IAM role"
  value       = aws_iam_role.builder_instance.arn
}

output "build_security_group_id" {
  description = "ID of the builder security group"
  value       = aws_security_group.build.id
}

output "sns_topic_arn" {
  description = "ARN of the build-failure notification SNS topic"
  value       = aws_sns_topic.pipeline.arn
}

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for builder run-command output"
  value       = aws_cloudwatch_log_group.builds.name
}
