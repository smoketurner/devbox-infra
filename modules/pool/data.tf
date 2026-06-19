# Data sources for the pool module

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

# IAM policy documents

data "aws_iam_policy_document" "control_plane_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.${local.aws_dns_suffix}"]
    }
  }
}

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

data "aws_iam_policy_document" "control_plane_runtime" {
  # Adopt-only: read the ASG, maintain desired capacity, protect Claimed
  # instances, and terminate released ones. Hook completion is the host's job
  # (devbox-agent), so CompleteLifecycleAction is intentionally absent here.
  statement {
    sid    = "AutoScalingActions"
    effect = "Allow"

    actions = [
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:SetDesiredCapacity",
      "autoscaling:TerminateInstanceInAutoScalingGroup",
      "autoscaling:SetInstanceProtection",
    ]

    resources = ["arn:${local.aws_partition}:autoscaling:${local.aws_region}:${local.aws_account_id}:autoScalingGroup:*:autoScalingGroupName/${local.asg_name}"]
  }

  # DescribeInstances (used to enrich DevboxDoc with type/AMI/subnet) does not
  # support resource-level permissions.
  statement {
    sid       = "EC2DescribeInstances"
    effect    = "Allow"
    actions   = ["ec2:DescribeInstances"]
    resources = ["*"]
  }

  statement {
    sid    = "EC2CreateTags"
    effect = "Allow"

    actions = ["ec2:CreateTags"]

    resources = ["*"]

    condition {
      test     = "ForAllValues:StringLike"
      variable = "aws:TagKeys"
      values   = ["devbox:*"]
    }
  }
}
