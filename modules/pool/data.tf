# Data sources for the pool module

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

# Resolve the workspace snapshot id at plan time. resolve:ssm is not valid for a
# block-device-mapping snapshot_id (only the launch template's top-level
# image_id), so a new snapshot enters the launch template on the next apply, which
# bumps its version; the agent's warming-time git fetch closes the gap to HEAD.
data "aws_ssm_parameter" "workspace_snapshot" {
  count = var.workspace_volume_enabled ? 1 : 0
  name  = var.workspace_snapshot_ssm_parameter
}

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

# Host runtime: the warm-up agent self-tags its own instance devbox:ready=true.
# "Own instance only" is not expressible in IAM (no policy variable for the
# caller's own instance id), so this is scoped by resource type (instance/*) and
# restricted to the devbox:ready tag key — it provably cannot touch devbox:owner
# (the SSH authorization tag, applied by the control plane).
data "aws_iam_policy_document" "host_runtime" {
  statement {
    sid       = "SelfTagReady"
    effect    = "Allow"
    actions   = ["ec2:CreateTags"]
    resources = ["arn:${local.aws_partition}:ec2:${local.aws_region}:${local.aws_account_id}:instance/*"]

    condition {
      test     = "ForAllValues:StringEquals"
      variable = "aws:TagKeys"
      values   = ["devbox:ready"]
    }
  }

  # The warming agent reads the GitHub App private key on-box to mint a 1h
  # read-only installation token for the /workspace fetch (devbox-agent
  # github_token.rs). SecureString on the default alias/aws/ssm key needs no
  # explicit kms:Decrypt; add one only if the parameter moves to a CMK.
  dynamic "statement" {
    for_each = var.github_app_private_key_param_arn != "" ? [1] : []
    content {
      sid       = "ReadGitHubAppKey"
      effect    = "Allow"
      actions   = ["ssm:GetParameter"]
      resources = [var.github_app_private_key_param_arn]
    }
  }
}

