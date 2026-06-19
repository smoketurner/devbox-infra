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

data "aws_iam_policy_document" "control_plane_runtime" {
  statement {
    sid    = "AutoScalingActions"
    effect = "Allow"

    actions = [
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:SetDesiredCapacity",
      "autoscaling:TerminateInstanceInAutoScalingGroup",
      "autoscaling:SetInstanceProtection",
      "autoscaling:CompleteLifecycleAction",
    ]

    resources = ["arn:${local.aws_partition}:autoscaling:${local.aws_region}:${local.aws_account_id}:autoScalingGroup:*:autoScalingGroupName/${local.asg_name}"]
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
