variable "name_prefix" {
  description = "Prefix for resource names (e.g., devbox-dev)"
  type        = string
}

variable "environment" {
  description = "Environment name (e.g., dev)"
  type        = string
}

variable "vpc_id" {
  description = "VPC the ALB and Fargate service run in (the egress VPC: has NAT for OIDC token exchange, AWS APIs, DSQL, and ECR)"
  type        = string
}

variable "subnet_ids" {
  description = "Private subnet IDs (with NAT egress) for the internal ALB and the Fargate service"
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "At least two subnets (across AZs) are required."
  }
}

variable "ingress_cidrs" {
  description = "CIDRs allowed to reach the internal ALB (e.g., the workload VPC and any VPN/peered ranges)"
  type        = list(string)
}

variable "pool_id" {
  description = "Pool identifier the reconciler adopts (ASG = devbox-pool-<pool_id>)"
  type        = string
  default     = "default"
}

variable "target_warm_pool_size" {
  description = "Number of unclaimed Ready instances the reconciler maintains"
  type        = number
  default     = 2
}

# --- Container / service sizing ---

variable "image_tag" {
  description = "Tag of the devbox-server image to deploy from the module's ECR repository"
  type        = string
  default     = "latest"
}

variable "container_port" {
  description = "Port the devbox-server listens on"
  type        = number
  default     = 3000
}

variable "desired_count" {
  description = "Number of Fargate tasks (the reconciler is leader-locked, so >1 is for API/UI availability)"
  type        = number
  default     = 2
}

variable "cpu" {
  description = "Fargate task CPU units"
  type        = number
  default     = 512
}

variable "memory" {
  description = "Fargate task memory (MiB)"
  type        = number
  default     = 1024
}

variable "log_retention_days" {
  description = "CloudWatch log retention for the service"
  type        = number
  default     = 30
}

variable "dsql_deletion_protection" {
  description = "Whether to enable deletion protection on the DSQL cluster"
  type        = bool
  default     = true
}

# --- TLS + Vouch OIDC ---

variable "certificate_arn" {
  description = "ACM certificate ARN for the ALB HTTPS listener (required for OIDC, which needs HTTPS)"
  type        = string
}

variable "ssl_policy" {
  description = "ALB HTTPS listener SSL policy"
  type        = string
  default     = "ELBSecurityPolicy-TLS13-1-2-2021-06"
}

# OIDC endpoints default to Vouch (https://vouch.sh/docs/applications/). Override
# for a different Vouch region or IdP. See the Vouch discovery document:
# https://us.vouch.sh/.well-known/openid-configuration
variable "oidc_issuer" {
  description = "OIDC issuer URL"
  type        = string
  default     = "https://us.vouch.sh"
}

variable "oidc_authorization_endpoint" {
  description = "OIDC authorization endpoint"
  type        = string
  default     = "https://us.vouch.sh/oauth/authorize"
}

variable "oidc_token_endpoint" {
  description = "OIDC token endpoint"
  type        = string
  default     = "https://us.vouch.sh/oauth/token"
}

variable "oidc_user_info_endpoint" {
  description = "OIDC user info endpoint"
  type        = string
  default     = "https://us.vouch.sh/oauth/userinfo"
}

variable "oidc_jwks_uri" {
  description = "JWKS URI the server uses to validate bearer tokens (CLI/agents)"
  type        = string
  default     = "https://us.vouch.sh/oauth/jwks"
}

variable "auth_principal_claim" {
  description = "JWT claim used as the principal/owner; MUST match the Vouch SSH cert principal (a Unix-safe username)"
  type        = string
  default     = "sub"
}

variable "oidc_client_id" {
  description = "OIDC client ID. Register an app in the Vouch dashboard with redirect URI https://<alb-domain>/oauth2/idpresponse."
  type        = string
}

variable "oidc_client_secret" {
  description = "OIDC client secret (source from a secrets backend / TF_VAR, never commit)"
  type        = string
  sensitive   = true
}

variable "oidc_scope" {
  description = "OIDC scopes to request (Vouch supports openid and email)"
  type        = string
  default     = "openid email"
}

# --- CI/CD (GitHub Actions OIDC deploy role) ---

variable "github_repository" {
  description = "GitHub repo (owner/name) allowed to assume the CI/CD deploy role; empty disables it"
  type        = string
  default     = ""
}

variable "github_oidc_provider_arn" {
  description = "Existing GitHub Actions OIDC provider ARN to reuse; empty creates one (account-global)"
  type        = string
  default     = ""
}

variable "github_allowed_refs" {
  description = "Git refs (sub-claim suffixes) allowed to assume the deploy role"
  type        = list(string)
  default     = ["ref:refs/heads/main", "ref:refs/tags/*"]
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
