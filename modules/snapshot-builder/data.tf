# Data sources for the snapshot-builder module

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

# SSM core lets the builder run the SSM agent so the automation reaches it with
# run-command (clone/warm) — same managed policy the pool host and image builder use.
data "aws_iam_policy" "ssm_core" {
  name = "AmazonSSMManagedInstanceCore"
}

# Assume-role trust documents.
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

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.${local.aws_dns_suffix}"]
    }
  }
}

# Automation role: launches and tears down the builder, runs the clone/warm
# command, snapshots the data volume, publishes the id, and GCs old snapshots.
data "aws_iam_policy_document" "snapshot_automation" {
  statement {
    sid    = "DescribeEc2"
    effect = "Allow"
    actions = [
      "ec2:DescribeInstances",
      "ec2:DescribeInstanceStatus",
      "ec2:DescribeVolumes",
      "ec2:DescribeSnapshots",
      "ec2:DescribeImages",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [local.aws_region]
    }
  }

  statement {
    sid       = "LaunchAndSnapshot"
    effect    = "Allow"
    actions   = ["ec2:RunInstances", "ec2:CreateSnapshot"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [local.aws_region]
    }
  }

  # Tag only resources created by RunInstances/CreateSnapshot, never arbitrary
  # existing resources.
  statement {
    sid       = "TagOnCreate"
    effect    = "Allow"
    actions   = ["ec2:CreateTags"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "ec2:CreateAction"
      values   = ["RunInstances", "CreateSnapshot"]
    }
  }

  # Delete only this pipeline's workspace snapshots (GC step).
  statement {
    sid       = "DeleteWorkspaceSnapshots"
    effect    = "Allow"
    actions   = ["ec2:DeleteSnapshot"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "ec2:ResourceTag/devbox:role"
      values   = ["workspace-snapshot"]
    }
  }

  # Terminate only this pipeline's builder, never pool hosts.
  statement {
    sid       = "TerminateBuilder"
    effect    = "Allow"
    actions   = ["ec2:TerminateInstances"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "ec2:ResourceTag/devbox:role"
      values   = ["snapshot-builder"]
    }
  }

  # The clone-warm doc name embeds sha256(script) and is replaced on every script
  # change; the automation always calls the current one by name. Grant the name prefix,
  # not the exact hashed ARN, so a scheduled run never races a script-change apply.
  statement {
    sid     = "RunCloneWarm"
    effect  = "Allow"
    actions = ["ssm:SendCommand"]
    resources = [
      "arn:${local.aws_partition}:ssm:${local.aws_region}:${local.aws_account_id}:document/${local.name_prefix}-clone-warm-*",
      "arn:${local.aws_partition}:ec2:${local.aws_region}:${local.aws_account_id}:instance/*",
    ]
  }

  statement {
    sid    = "PollCommandsAndInstances"
    effect = "Allow"
    actions = [
      "ssm:GetCommandInvocation",
      "ssm:ListCommands",
      "ssm:ListCommandInvocations",
      "ssm:DescribeInstanceInformation",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "ReadParameters"
    effect    = "Allow"
    actions   = ["ssm:GetParameter", "ssm:GetParameters"]
    resources = [local.ami_parameter_arn, local.snapshot_parameter_arn]
  }

  statement {
    sid       = "PublishSnapshotParameter"
    effect    = "Allow"
    actions   = ["ssm:PutParameter"]
    resources = [local.snapshot_parameter_arn]
  }

  statement {
    sid       = "PassBuilderRole"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.builder_instance.arn]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ec2.${local.aws_dns_suffix}"]
    }
  }

  # Single CMK (var.ami_kms_key_arn) for both the golden AMI's encrypted root volume
  # (RunInstances creates the launch grant) and the data volume + snapshot. The key's
  # policy can't list this role without a module cycle, so access goes through IAM +
  # the key's root-account delegation.
  statement {
    sid    = "UseEncryptionKeys"
    effect = "Allow"
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
      "kms:CreateGrant",
    ]
    resources = [var.ami_kms_key_arn]
  }
}

# EventBridge role: start the build automation on schedule and pass it the
# automation role (byte-for-byte the pool's ami_refresh_events pattern).
data "aws_iam_policy_document" "snapshot_events" {
  statement {
    sid       = "StartAutomation"
    effect    = "Allow"
    actions   = ["ssm:StartAutomationExecution"]
    resources = ["arn:${local.aws_partition}:ssm:${local.aws_region}:${local.aws_account_id}:automation-definition/${aws_ssm_document.snapshot_build.name}:*"]
  }

  statement {
    sid       = "PassAutomationRole"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.snapshot_automation.arn]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ssm.${local.aws_dns_suffix}"]
    }
  }
}

# Builder instance: present its AWS identity to the control plane for a
# repo-scoped clone token (the App private key is no longer on the box) and write
# its run-command output to CloudWatch. EBS/KMS access for the data volume is
# granted by the UseDataVolumeKey statement below on the single CMK
# (var.ami_kms_key_arn); ec2 snapshot/run/terminate live on the automation role,
# never on the token-holding box.
data "aws_iam_policy_document" "builder_instance" {
  statement {
    sid       = "GetWebIdentityToken"
    effect    = "Allow"
    actions   = ["sts:GetWebIdentityToken"]
    resources = ["*"]
  }

  statement {
    sid    = "WriteBuildLogs"
    effect = "Allow"
    actions = [
      # CreateLogGroup is required even though Terraform pre-creates the group: the
      # SSM agent's CloudWatch uploader calls it up front and, lacking the action,
      # gets AccessDenied and silently abandons the whole upload (CWUrl stays null,
      # no streams). The other three are the actual stream writes.
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
    ]
    resources = ["${aws_cloudwatch_log_group.builds.arn}:*"]
  }

  # The data volume is encrypted with the single CMK (var.ami_kms_key_arn) and
  # attached to this instance. Encrypt + ReEncrypt* cover the async restore when a
  # volume is created from the encrypted snapshot; granted via IAM on the key's
  # root-account delegation because the key lives in image-builder, which can't list
  # this role without a module cycle.
  statement {
    sid    = "UseDataVolumeKey"
    effect = "Allow"
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
      "kms:CreateGrant",
    ]
    resources = [var.ami_kms_key_arn]
  }
}

# Allow EventBridge to publish failure notifications to the SNS topic.
data "aws_iam_policy_document" "sns_topic_policy" {
  statement {
    sid    = "AllowEventBridgePublish"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["events.${local.aws_dns_suffix}"]
    }

    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.pipeline.arn]
  }
}
