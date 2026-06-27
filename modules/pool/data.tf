# Data sources for the pool module

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

# Resolve the workspace snapshot id at plan time. resolve:ssm is not valid for a
# block-device-mapping snapshot_id (only the launch template's top-level
# image_id), so a new snapshot enters the launch template on the next apply, which
# bumps its version; the agent's warming-time git fetch closes the gap to HEAD.
data "aws_ssm_parameter" "workspace_snapshot" {
  name = var.workspace_snapshot_ssm_parameter
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
# caller's own instance id), so this is scoped as tightly as a shared instance
# profile allows: the devbox:ready key only (provably cannot touch devbox:owner,
# the SSH authorization tag applied by the control plane), the value "true" only,
# and only on instances in this pool's ASG. A claimant with root on the box can
# read these instance-profile creds via IMDS, so this policy — not on-box
# controls — is the durable boundary. Residual: a root claimant could mark a
# sibling pool box ready slightly early, which warmup would do moments later.
data "aws_iam_policy_document" "host_runtime" {
  statement {
    sid       = "SelfTagReady"
    effect    = "Allow"
    actions   = ["ec2:CreateTags"]
    resources = ["arn:${local.aws_partition}:ec2:${local.aws_region}:${local.aws_account_id}:instance/*"]

    # Only the devbox:ready key may be written (blocks devbox:owner).
    condition {
      test     = "ForAllValues:StringEquals"
      variable = "aws:TagKeys"
      values   = ["devbox:ready"]
    }

    # ...and only with the value "true".
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/devbox:ready"
      values   = ["true"]
    }

    # ...and only on instances in this pool's ASG, whose aws:autoscaling:groupName
    # tag the ASG applies at launch. Use local.asg_name (a pure string from
    # var.pool_id), not aws_autoscaling_group.pool.name, to avoid a dependency
    # cycle: this policy -> ASG -> launch template -> instance profile -> role ->
    # this policy.
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/aws:autoscaling:groupName"
      values   = [local.asg_name]
    }
  }

  # The warming agent presents this instance's AWS identity to the control plane
  # to obtain a short-lived, repo-scoped GitHub token (the App private key no
  # longer lives on the box). The only credential it needs is its own AWS
  # web-identity token: GetWebIdentityToken on `:self` requires no other
  # permission and is implicitly scoped to this instance's own identity.
  statement {
    sid       = "GetWebIdentityToken"
    effect    = "Allow"
    actions   = ["sts:GetWebIdentityToken"]
    resources = ["*"]
  }
}

