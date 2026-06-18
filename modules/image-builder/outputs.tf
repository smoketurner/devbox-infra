output "pipeline_arn" {
  description = "ARN of the Image Builder pipeline"
  value       = aws_imagebuilder_image_pipeline.this.arn
}

output "distribution_configuration_arn" {
  description = "ARN of the distribution configuration"
  value       = aws_imagebuilder_distribution_configuration.this.arn
}

output "ssm_parameter_name" {
  description = "Name of the SSM parameter storing the latest AMI ID"
  value       = aws_ssm_parameter.ami_id.name
}

output "ssm_parameter_arn" {
  description = "ARN of the SSM parameter storing the latest AMI ID"
  value       = aws_ssm_parameter.ami_id.arn
}

output "sns_topic_arn" {
  description = "ARN of the pipeline notification SNS topic"
  value       = aws_sns_topic.pipeline.arn
}

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for build logs"
  value       = aws_cloudwatch_log_group.builds.name
}

output "build_security_group_id" {
  description = "ID of the build instance security group"
  value       = aws_security_group.build.id
}

output "build_instance_role_arn" {
  description = "ARN of the build instance IAM role"
  value       = aws_iam_role.build_instance.arn
}
