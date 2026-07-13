data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

# Resolves the account's OIDC issuer URL, fed to the server as DEVBOX_AGENT_OIDC_ISSUER.
data "aws_iam_outbound_web_identity_federation" "agent_oidc" {
  depends_on = [aws_iam_outbound_web_identity_federation.agent_oidc]
}

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
    sid       = "AutoScalingDescribe"
    effect    = "Allow"
    actions   = ["autoscaling:DescribeAutoScalingGroups"]
    resources = ["*"] # Describe* is account-level; no resource-level scoping
  }

  statement {
    sid    = "AutoScalingManage"
    effect = "Allow"
    actions = [
      "autoscaling:UpdateAutoScalingGroup", # reconciler sets desired_capacity
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

  # The claim handler (inline, at claim time) and the reconciler
  # (apply_pending_owner_tags / the Archiving step, re-asserting) are the
  # CreateTags callers: devbox:owner (always) and devbox:owner-email plus
  # devbox:session-restore (when present) at claim; devbox:archive-session at
  # release --keep.
  statement {
    sid       = "EC2CreateTags"
    effect    = "Allow"
    actions   = ["ec2:CreateTags"]
    resources = ["*"]

    condition {
      test     = "ForAllValues:StringEquals"
      variable = "aws:TagKeys"
      values = [
        "devbox:owner",
        "devbox:owner-email",
        "devbox:session-restore",
        "devbox:archive-session",
      ]
    }

    # Scope to instances in this pool's ASG. The server tags the just-claimed
    # instance, which is InService and so already carries the groupName tag.
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/aws:autoscaling:groupName"
      values   = [local.asg_name]
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

  # The control plane owns the GitHub App private key: it reads the SSM
  # SecureString to sign App JWTs and mint repo-scoped installation tokens for
  # devbox hosts. This is the only legitimate reader of the parameter (the pool
  # and builder roles no longer can). SecureString on the default alias/aws/ssm
  # key needs no explicit kms:Decrypt; add one only if it moves to a CMK.
  statement {
    sid       = "ReadGitHubAppKey"
    effect    = "Allow"
    actions   = ["ssm:GetParameter"]
    resources = [var.github_app_key_param_arn]
  }

  # Session archives: the server presigns PUT (archive upload at release
  # --keep) and GET (restore at claim --resume) URLs against this role — a
  # presigned URL executes with the signer's permissions, so these are the only
  # S3 grants in the platform (devbox hosts have none).
  statement {
    sid    = "SessionArchives"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
    ]
    resources = ["${aws_s3_bucket.sessions.arn}/sessions/*"]
  }
}
