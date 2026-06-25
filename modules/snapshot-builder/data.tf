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

  statement {
    sid     = "RunCloneWarm"
    effect  = "Allow"
    actions = ["ssm:SendCommand"]
    resources = [
      aws_ssm_document.clone_warm.arn,
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

  # Use both CMKs when launching the builder: the image-builder AMI key for the
  # golden AMI's encrypted root volume (RunInstances creates the launch grant), and
  # the workspace key for the encrypted data volume + snapshot. The AMI key's
  # policy can't list this role without a module cycle, so access to it goes
  # through IAM + that key's root-account delegation.
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
    resources = [aws_kms_key.workspace.arn, var.ami_kms_key_arn]
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

# Builder instance: read the GitHub App private key (to mint a clone token) and
# write its run-command output to CloudWatch. EBS/KMS access for the data volume
# is granted via the workspace key policy below; ec2 snapshot/run/terminate live
# on the automation role, never on the token-holding box.
data "aws_iam_policy_document" "builder_instance" {
  statement {
    sid       = "ReadGitHubAppKey"
    effect    = "Allow"
    actions   = ["ssm:GetParameter", "ssm:GetParameters"]
    resources = [var.github_app_private_key_param_arn]
  }

  statement {
    sid    = "WriteBuildLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
    ]
    resources = ["${aws_cloudwatch_log_group.builds.arn}:*"]
  }
}

# Workspace snapshot CMK policy. Mirrors the image-builder AMI key: root manages,
# the builder role uses it for the data volume, and the AutoScaling SLR can use it
# (+ conditioned CreateGrant) so pool ASGs launch from the encrypted snapshot.
data "aws_iam_policy_document" "kms_key" {
  statement {
    sid    = "EnableRootAccountAccess"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:${local.aws_partition}:iam::${local.aws_account_id}:root"]
    }

    actions   = ["kms:*"]
    resources = ["*"]
  }

  # The builder instance profile (the volume is attached to it) and the automation
  # role (the RunInstances caller that creates the EBS-encryption grant). EC2's EBS
  # grant flow evaluates the key policy for the launching principal, so the
  # automation role must be listed here, not only granted via IAM + root-enable.
  statement {
    sid    = "AllowBuilderUse"
    effect = "Allow"

    principals {
      type = "AWS"
      identifiers = [
        aws_iam_role.builder_instance.arn,
        aws_iam_role.snapshot_automation.arn,
      ]
    }

    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
      "kms:CreateGrant",
    ]

    resources = ["*"]
  }

  statement {
    sid    = "AllowAutoScalingUse"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [local.autoscaling_slr_arn]
    }

    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]

    resources = ["*"]
  }

  statement {
    sid    = "AllowAutoScalingCreateGrant"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [local.autoscaling_slr_arn]
    }

    actions   = ["kms:CreateGrant"]
    resources = ["*"]

    condition {
      test     = "Bool"
      variable = "kms:GrantIsForAWSResource"
      values   = ["true"]
    }
  }

  dynamic "statement" {
    for_each = length(var.trusted_account_ids) > 0 ? [1] : []
    content {
      sid    = "AllowCrossAccountUse"
      effect = "Allow"

      principals {
        type        = "AWS"
        identifiers = [for id in var.trusted_account_ids : "arn:${local.aws_partition}:iam::${id}:root"]
      }

      actions = [
        "kms:Decrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:DescribeKey",
        "kms:CreateGrant",
      ]

      resources = ["*"]
    }
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
