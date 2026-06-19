# Data sources for the pool module

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

# AMI-refresh executor: assume-role trust for SSM Automation and EventBridge.
data "aws_iam_policy_document" "ssm_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ssm.${local.aws_dns_suffix}"]
    }
  }
}

data "aws_iam_policy_document" "events_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["events.${local.aws_dns_suffix}"]
    }
  }
}

# Automation role: start an instance refresh on this pool's ASG.
data "aws_iam_policy_document" "ami_refresh_automation" {
  statement {
    sid       = "StartInstanceRefresh"
    effect    = "Allow"
    actions   = ["autoscaling:StartInstanceRefresh"]
    resources = [aws_autoscaling_group.pool.arn]
  }

  # Describe actions do not support resource-level permissions.
  statement {
    sid    = "DescribeRefresh"
    effect = "Allow"
    actions = [
      "autoscaling:DescribeInstanceRefreshes",
      "autoscaling:DescribeAutoScalingGroups",
    ]
    resources = ["*"]
  }
}

# EventBridge role: start the automation and pass it the automation role.
data "aws_iam_policy_document" "ami_refresh_events" {
  statement {
    sid       = "StartAutomation"
    effect    = "Allow"
    actions   = ["ssm:StartAutomationExecution"]
    resources = ["arn:${local.aws_partition}:ssm:${local.aws_region}:${local.aws_account_id}:automation-definition/${aws_ssm_document.ami_refresh.name}:*"]
  }

  statement {
    sid       = "PassAutomationRole"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.ami_refresh_automation.arn]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ssm.${local.aws_dns_suffix}"]
    }
  }
}

# IAM policy documents

data "aws_iam_policy_document" "host_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.${local.aws_dns_suffix}"]
    }
  }
}

# AmazonSSMManagedInstanceCore lets the host run the SSM agent so callers can
# reach sshd over an AWS-StartSSHSession tunnel without a public IP or bastion.
data "aws_iam_policy" "ssm_core" {
  name = "AmazonSSMManagedInstanceCore"
}

# Host runtime: the warm-up agent releases its own ASG launch lifecycle hook.
data "aws_iam_policy_document" "host_runtime" {
  statement {
    sid       = "CompleteWarmupHook"
    effect    = "Allow"
    actions   = ["autoscaling:CompleteLifecycleAction"]
    resources = ["arn:${local.aws_partition}:autoscaling:${local.aws_region}:${local.aws_account_id}:autoScalingGroup:*:autoScalingGroupName/${local.asg_name}"]
  }

  # DescribeLifecycleHooks does not support resource-level permissions.
  statement {
    sid       = "DiscoverLifecycleHooks"
    effect    = "Allow"
    actions   = ["autoscaling:DescribeLifecycleHooks"]
    resources = ["*"]
  }
}

