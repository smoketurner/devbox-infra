data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

# ECS tasks assume-role trust (shared by the execution and task roles).
data "aws_iam_policy_document" "ecs_tasks_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.${local.aws_dns_suffix}"]
    }
  }
}

# Managed policy for the execution role (pull from ECR, write logs).
data "aws_iam_policy" "ecs_task_execution" {
  name = "AmazonECSTaskExecutionRolePolicy"
}

# Task (runtime) role: the adopt-only control plane.
data "aws_iam_policy_document" "task" {
  statement {
    sid    = "AutoScalingActions"
    effect = "Allow"
    actions = [
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:SetDesiredCapacity",
      "autoscaling:TerminateInstanceInAutoScalingGroup",
      "autoscaling:SetInstanceProtection",
    ]
    resources = [local.asg_arn]
  }

  statement {
    sid       = "EC2DescribeInstances"
    effect    = "Allow"
    actions   = ["ec2:DescribeInstances"]
    resources = ["*"]
  }

  statement {
    sid       = "EC2CreateTags"
    effect    = "Allow"
    actions   = ["ec2:CreateTags"]
    resources = ["*"]

    condition {
      test     = "ForAllValues:StringLike"
      variable = "aws:TagKeys"
      values   = ["devbox:*"]
    }
  }

  # IAM-authenticated DSQL connection as the custom db_role (not admin). The
  # role is created and mapped to this task role by the bootstrap SQL.
  statement {
    sid       = "DsqlConnect"
    effect    = "Allow"
    actions   = ["dsql:DbConnect"]
    resources = [aws_dsql_cluster.this.arn]
  }
}
