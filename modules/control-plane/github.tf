# Keyless CI/CD. GitHub Actions assumes this role via OIDC (no long-lived access
# keys) to push the devbox-server image to ECR and force a new ECS deployment.
# Disabled unless `github_repository` is set. The OIDC provider is account-global;
# set `github_oidc_provider_arn` to reuse an existing one.

locals {
  create_github_deploy = var.github_repository != ""
  github_oidc_arn = var.github_oidc_provider_arn != "" ? var.github_oidc_provider_arn : (
    length(aws_iam_openid_connect_provider.github) > 0 ? aws_iam_openid_connect_provider.github[0].arn : ""
  )
}

resource "aws_iam_openid_connect_provider" "github" {
  count = local.create_github_deploy && var.github_oidc_provider_arn == "" ? 1 : 0

  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]

  # GitHub's OIDC thumbprints. AWS no longer validates these for this provider,
  # but the field is required; both well-known values are included.
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
  ]

  tags = local.tags
}

data "aws_iam_policy_document" "github_assume" {
  count = local.create_github_deploy ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.github_oidc_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Restrict to the configured repo + refs (main and tags by default).
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [for ref in var.github_allowed_refs : "repo:${var.github_repository}:${ref}"]
    }
  }
}

data "aws_iam_policy_document" "github_deploy" {
  count = local.create_github_deploy ? 1 : 0

  statement {
    sid       = "EcrAuth"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "EcrPushPull"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]
    resources = [aws_ecr_repository.server.arn]
  }

  # Roll the service. RegisterTaskDefinition / Describe* don't support
  # resource-level permissions.
  statement {
    sid    = "EcsDeploy"
    effect = "Allow"
    actions = [
      "ecs:RegisterTaskDefinition",
      "ecs:DeregisterTaskDefinition",
      "ecs:DescribeTaskDefinition",
      "ecs:DescribeServices",
      "ecs:UpdateService",
    ]
    resources = ["*"]
  }

  # Allow passing the task's execution/runtime roles to ECS on deploy.
  statement {
    sid       = "PassTaskRoles"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.execution.arn, aws_iam_role.task.arn]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.${local.aws_dns_suffix}"]
    }
  }
}

resource "aws_iam_role" "github_deploy" {
  count = local.create_github_deploy ? 1 : 0

  name               = "${local.name_prefix}-github-deploy"
  assume_role_policy = data.aws_iam_policy_document.github_assume[0].json

  tags = local.tags
}

resource "aws_iam_role_policy" "github_deploy" {
  count = local.create_github_deploy ? 1 : 0

  name   = "${local.name_prefix}-github-deploy"
  role   = aws_iam_role.github_deploy[0].id
  policy = data.aws_iam_policy_document.github_deploy[0].json
}
