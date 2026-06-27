# Data sources for the image-builder module

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

# Managed IAM policy lookups
data "aws_iam_policy" "image_builder" {
  name = "EC2InstanceProfileForImageBuilder"
}

data "aws_iam_policy" "ssm_core" {
  name = "AmazonSSMManagedInstanceCore"
}

# Baseline workflow permissions for the pipeline execution role (replaces the
# AWSServiceRoleForImageBuilder service-linked role for build/test/distribution).
data "aws_iam_policy" "execution" {
  name = "EC2ImageBuilderExecutionPolicy"
}

# IAM policy documents
data "aws_iam_policy_document" "build_instance_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.${local.aws_dns_suffix}"]
    }
  }
}

data "aws_iam_policy_document" "s3_access" {
  count = var.s3_bucket_arn != "" ? 1 : 0

  statement {
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${var.s3_bucket_arn}/*"]
  }
}

data "aws_iam_policy_document" "secrets_access" {
  count = length(var.secrets_arns) > 0 ? 1 : 0

  statement {
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = var.secrets_arns
  }
}

data "aws_iam_policy_document" "imagebuilder_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["imagebuilder.${local.aws_dns_suffix}"]
    }
  }
}

data "aws_iam_policy_document" "lifecycle" {
  statement {
    sid    = "ImageLifecycleActions"
    effect = "Allow"

    actions = [
      "ec2:DeregisterImage",
      "ec2:DescribeImages",
      "ec2:DescribeImageAttribute",
      "ec2:DeleteSnapshot",
      "ec2:DescribeSnapshots",
      "imagebuilder:DeleteImage",
      "imagebuilder:GetImage",
      "imagebuilder:ListImages",
      "tag:GetResources",
    ]

    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [local.aws_region]
    }
  }
}

# Feature permissions added to the execution role beyond the managed baseline:
# publish the output AMI ID to the SSM parameter during distribution, and
# describe images so Systems Manager can validate the aws:ec2:image value.
data "aws_iam_policy_document" "execution" {
  statement {
    sid       = "PublishAmiParameter"
    effect    = "Allow"
    actions   = ["ssm:PutParameter"]
    resources = ["arn:${local.aws_partition}:ssm:${local.aws_region}:${local.aws_account_id}:parameter${var.ssm_parameter_path}"]
  }
}

# SNS topic policy allowing EventBridge to publish notifications
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

# SSM parameter for latest AL2023 AMI (base image for recipe).
# arm64 (Graviton) on the 6.18 kernel line.
data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.18-arm64"
}

# Workspace snapshot CMK, resolved by alias to avoid a module cycle with
# snapshot-builder (which already depends on this module). The key's policy
# delegates to the account root, so the IAM grant below is sufficient — no
# snapshot-builder change. Gated on the test-mount toggle so a bootstrap apply
# (before snapshot-builder exists) does not fail resolving a missing alias.
data "aws_kms_key" "workspace" {
  count  = var.enable_test_stage_workspace_mount ? 1 : 0
  key_id = "alias/${var.name_prefix}-snapshot-builder-workspace"
}

# Test-stage workspace-mount permissions for the build instance role (used by both
# build and test instances). Lets the test instance create + attach the workspace
# snapshot volume, mount it, and run warm-up against the real AMI. Scoped by
# region/tag/key; the destructive ops (detach/delete) are limited to volumes this
# test created (devbox:role=workspace-test).
data "aws_iam_policy_document" "build_instance_test_mount" {
  count = var.enable_test_stage_workspace_mount ? 1 : 0

  statement {
    sid       = "ReadSnapshotParam"
    effect    = "Allow"
    actions   = ["ssm:GetParameter"]
    resources = ["arn:${local.aws_partition}:ssm:${local.aws_region}:${local.aws_account_id}:parameter${var.workspace_snapshot_param}"]
  }

  # Test-stage warm-up requests a repo-scoped GitHub token from the control plane
  # using this instance's AWS identity (the App private key is no longer on the box).
  statement {
    sid       = "GetWebIdentityToken"
    effect    = "Allow"
    actions   = ["sts:GetWebIdentityToken"]
    resources = ["*"]
  }

  # Full EBS-encryption action set, matching the snapshot-builder roles and the
  # AutoScaling SLR that are already allowed on this key. Encrypt + ReEncrypt* are
  # required for the async restore when creating an encrypted volume from the
  # encrypted snapshot; without them the volume errors out and EC2 deletes it.
  statement {
    sid    = "UseWorkspaceKey"
    effect = "Allow"
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
      "kms:CreateGrant",
    ]
    resources = [data.aws_kms_key.workspace[0].arn]
  }

  # Create the volume, attach it to this ephemeral test instance, and flip its
  # delete-on-termination. Region-scoped: these target the throwaway test instance,
  # which carries no stable tag to scope on.
  statement {
    sid    = "CreateAndAttachWorkspaceTestVolume"
    effect = "Allow"
    actions = [
      "ec2:CreateVolume",
      "ec2:DescribeVolumes",
      "ec2:AttachVolume",
      "ec2:ModifyInstanceAttribute",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [local.aws_region]
    }
  }

  # Tag only the volume created by CreateVolume, never existing resources.
  statement {
    sid       = "TagWorkspaceTestVolumeOnCreate"
    effect    = "Allow"
    actions   = ["ec2:CreateTags"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "ec2:CreateAction"
      values   = ["CreateVolume"]
    }
  }

  # Detach/delete only volumes this test created.
  statement {
    sid    = "ReleaseWorkspaceTestVolume"
    effect = "Allow"
    actions = [
      "ec2:DetachVolume",
      "ec2:DeleteVolume",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "ec2:ResourceTag/devbox:role"
      values   = ["workspace-test"]
    }
  }

  # Warm-up self-tags the instance devbox:ready=true. Harmless here (the test
  # instance is not in the pool ASG, and claim discovery is ASG-only), so this
  # mirrors the pool's SelfTagReady minus the ASG-membership condition.
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

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/devbox:ready"
      values   = ["true"]
    }
  }
}

# KMS key policy for AMI encryption
data "aws_iam_policy_document" "kms_key" {
  # Allow the owning account full management
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

  # Allow Image Builder and EC2 to use the key for encryption/decryption
  statement {
    sid    = "AllowImageBuilderAndEC2"
    effect = "Allow"

    principals {
      type = "AWS"
      identifiers = [
        aws_iam_role.build_instance.arn,
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

  # Allow the EC2 Auto Scaling service-linked role to use the key when launching
  # pool instances from CMK-encrypted AMI snapshots. CreateGrant is split out
  # because it carries the GrantIsForAWSResource condition.
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

  # Allow trusted accounts to use the key (for cross-account AMI sharing)
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
