data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

# The image the service is currently running. CI owns the image (sha-pinned tags);
# Terraform reads it here so a task-def change (adding the proxy port + egress env)
# doesn't regress it to a stale tag, letting a single apply roll the service without
# a CI redeploy.
data "aws_ecs_service" "current" {
  service_name = local.name_prefix
  cluster_arn  = aws_ecs_cluster.this.arn
}

data "aws_ecs_container_definition" "current" {
  task_definition = data.aws_ecs_service.current.task_definition
  container_name  = "devbox-server"
}

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
  # (apply_pending_owner_tags, re-asserting) are the CreateTags callers; both
  # write exactly devbox:owner (always) and devbox:owner-email (when present).
  statement {
    sid       = "EC2CreateTags"
    effect    = "Allow"
    actions   = ["ec2:CreateTags"]
    resources = ["*"]

    condition {
      test     = "ForAllValues:StringEquals"
      variable = "aws:TagKeys"
      values   = ["devbox:owner", "devbox:owner-email"]
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
}
