output "asg_name" {
  description = "Name of the Auto Scaling Group (deterministic naming contract)"
  value       = aws_autoscaling_group.pool.name
}

output "asg_arn" {
  description = "ARN of the Auto Scaling Group"
  value       = aws_autoscaling_group.pool.arn
}

output "launch_template_id" {
  description = "ID of the Launch Template"
  value       = aws_launch_template.pool.id
}

output "launch_template_arn" {
  description = "ARN of the Launch Template"
  value       = aws_launch_template.pool.arn
}

output "lifecycle_hook_name" {
  description = "Name of the warm-up lifecycle hook"
  value       = aws_autoscaling_lifecycle_hook.warmup.name
}

output "control_plane_role_arn" {
  description = "ARN of the control-plane IAM role"
  value       = aws_iam_role.control_plane.arn
}

output "control_plane_role_name" {
  description = "Name of the control-plane IAM role"
  value       = aws_iam_role.control_plane.name
}

output "security_group_id" {
  description = "ID of the pool instances security group"
  value       = aws_security_group.pool.id
}

output "host_role_arn" {
  description = "ARN of the pool host (instance) IAM role"
  value       = aws_iam_role.host.arn
}

output "host_instance_profile_name" {
  description = "Name of the pool host instance profile"
  value       = aws_iam_instance_profile.host.name
}

output "control_plane_instance_profile_name" {
  description = "Name of the control-plane instance profile"
  value       = aws_iam_instance_profile.control_plane.name
}
