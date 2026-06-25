# GitHub App private key, stored once as an encrypted SSM SecureString and read
# on-box by two consumers that mint their own short-lived read-only installation
# tokens: the snapshot builder (cloning at build time) and the pool host agent
# (the /workspace warming fetch, devbox-agent github_token.rs). No off-box broker
# and no control-plane involvement. With the default alias/aws/ssm key, the
# readers need only ssm:GetParameter (no explicit kms:Decrypt) — same as the
# oidc_client_secret pattern.
#
# The variable carries a base64-encoded PEM (single-line input); decode it here so
# SSM holds the raw PEM both consumers expect (openssl dgst -sign and Rust
# EncodingKey::from_rsa_pem).
resource "aws_ssm_parameter" "github_app_private_key" {
  name        = "/devbox-${local.environment}/github-app-private-key"
  description = "GitHub App private key (PEM) for read-only workspace freshening"
  type        = "SecureString"
  value       = base64decode(var.github_app_private_key)

  tags = local.common_tags
}
