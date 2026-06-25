# Inputs for this environment. domain_name carries a sane default; the Vouch OIDC
# credentials come from registering the control-plane app in the Vouch dashboard,
# must not be committed, and are sourced via TF_VAR_* or a gitignored *.tfvars.

variable "domain_name" {
  description = "Public hostname for the control plane (Terraform issues the ACM cert and Route 53 alias for it)"
  type        = string
  default     = "smoketurner.devbox.farm"
}

variable "oidc_client_id" {
  description = "Client ID of the confidential dashboard Vouch app (used by the ALB OIDC flow)"
  type        = string
}

variable "oidc_client_secret" {
  description = "Client secret for the dashboard Vouch app; source via TF_VAR_oidc_client_secret, never commit"
  type        = string
  sensitive   = true
}

variable "github_app_id" {
  description = "GitHub App ID (or Client ID) for the read-only workspace-freshening App; JWT issuer when minting installation tokens"
  type        = string
}

variable "github_app_private_key" {
  description = "GitHub App private key, base64-encoded PEM (single-line, avoids multiline-PEM pain in tfvars/TF_VAR). Decoded to the raw PEM before storage in SSM. Source via TF_VAR_github_app_private_key, never commit."
  type        = string
  sensitive   = true

  validation {
    condition     = can(base64decode(var.github_app_private_key))
    error_message = "github_app_private_key must be a base64-encoded PEM."
  }
}

variable "workspace_repos" {
  description = "Git clone URLs seeded into the workspace snapshot, one checkout per repo under /workspace"
  type        = list(string)
  default     = []
}

variable "docker_images" {
  description = "Container images pre-pulled into the AMI's /var/lib/docker at build time so first container use is warm. Refreshed on AMI rebuild."
  type        = list(string)
  default     = []
}
