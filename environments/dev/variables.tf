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
