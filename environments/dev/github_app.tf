# GitHub App private key, stored once as an encrypted SSM SecureString and read
# only by the control plane (devbox-server). Hosts never read the key: the
# snapshot builder (cloning at build time) and the pool host agent (the
# /workspace warming fetch) authenticate to devbox-server with an AWS
# web-identity token (devbox-agent control_plane.rs), and the server mints a
# short-lived, repo-scoped read-only installation token on their behalf
# (POST /api/v1/agent/git-token, devbox-server github/minter.rs). With the
# default alias/aws/ssm key, the server needs only ssm:GetParameter (no explicit
# kms:Decrypt) — same as the oidc_client_secret pattern.
#
# The variable carries a base64-encoded PEM (single-line input); decode it here so
# SSM holds the raw PEM the server expects (Rust EncodingKey::from_rsa_pem).
resource "aws_ssm_parameter" "github_app_private_key" {
  name        = "/devbox-${local.environment}/github-app-private-key"
  description = "GitHub App private key (PEM) for read-only workspace freshening"
  type        = "SecureString"
  value       = base64decode(var.github_app_private_key)

  tags = local.common_tags
}
