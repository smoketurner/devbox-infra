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

data "aws_iam_policy_document" "lifecycle_assume_role" {
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
      "ec2:DeleteSnapshot",
      "ec2:DescribeSnapshots",
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

data "aws_iam_policy_document" "ssm_publish" {
  statement {
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
