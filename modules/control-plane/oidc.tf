# Dashboard OIDC login (app-side Authorization Code flow). The server gates the
# HTML dashboard on a Vouch login when AUTH_OIDC_CLIENT_ID / CLIENT_SECRET /
# REDIRECT_URI are set (see ecs.tf) — this replaces the dashboard OIDC gate that
# the (now removed) ALB used to perform, since the NLB is L4.
#
# The client secret is stored as an encrypted SSM SecureString and injected by
# the ECS execution role at task start, never as a plaintext task-definition env
# var. With the default `alias/aws/ssm` key, ssm:GetParameters is sufficient (no
# explicit kms:Decrypt grant needed).

resource "aws_ssm_parameter" "oidc_client_secret" {
  name        = "/${local.name_prefix}/oidc-client-secret"
  description = "Vouch dashboard OIDC client secret for the control-plane server"
  type        = "SecureString"
  value       = var.oidc_client_secret

  tags = local.tags
}

# Allow the ECS execution role to read the parameter so it can inject it as the
# AUTH_OIDC_CLIENT_SECRET env var on the container.
data "aws_iam_policy_document" "execution_secrets" {
  statement {
    sid       = "ReadOidcClientSecret"
    effect    = "Allow"
    actions   = ["ssm:GetParameters"]
    resources = [aws_ssm_parameter.oidc_client_secret.arn]
  }
}

resource "aws_iam_role_policy" "execution_secrets" {
  name   = "${local.name_prefix}-execution-secrets"
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.execution_secrets.json
}
