variable "name_prefix" {
  description = "Prefix for resource names (e.g., devbox-dev)"
  type        = string
}

variable "vpc_id" {
  description = "VPC the NLB and Fargate service run in (a dedicated control-plane VPC with a public subnet + internet gateway)"
  type        = string
}

variable "subnet_ids" {
  description = "Public subnet IDs (internet-gateway route) for the NLB and the public-IP Fargate tasks"
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 1
    error_message = "At least one subnet is required."
  }
}

variable "ingress_cidrs" {
  description = "CIDRs allowed to reach the public NLB on 443 (the API is bearer-token validated app-side)"
  type        = list(string)
}

variable "ingress_ipv6_cidrs" {
  description = "IPv6 CIDRs allowed to reach the dual-stack NLB on 443 (empty disables IPv6 ingress)"
  type        = list(string)
  default     = []
}

variable "pool_id" {
  description = "Pool identifier the reconciler adopts (ASG = devbox-pool-<pool_id>)"
  type        = string
  default     = "default"
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

variable "egress_proxy_port" {
  description = "Port the devbox-server's allowlisting CONNECT egress proxy listens on"
  type        = number
  default     = 3128
}

variable "egress_allowlist" {
  description = "Comma-separated hostnames devboxes may reach through the egress proxy (empty disables all egress through it)"
  type        = string
  default     = ""
}

variable "desired_count" {
  description = "Number of Fargate tasks (the reconciler gates each tick on a TTL lock row in DSQL so only one instance acts; >1 is for API/UI availability)"
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
  default     = 7
}

variable "dsql_deletion_protection" {
  description = "Whether to enable deletion protection on the DSQL cluster"
  type        = bool
  default     = true
}

# --- TLS + Vouch OIDC ---

variable "domain_name" {
  description = "Public hostname for the control plane (e.g., cp.devbox.farm); Terraform issues an ACM cert and Route 53 alias for it"
  type        = string
}

variable "route53_zone_id" {
  description = "Route 53 hosted zone ID that owns domain_name (for the ACM validation and alias records)"
  type        = string
}

variable "ssl_policy" {
  description = "TLS security policy for the NLB TLS listener"
  type        = string
  default     = "ELBSecurityPolicy-TLS13-1-2-2021-06"
}

# Dashboard login is performed app-side by the server (OIDC Authorization Code
# flow), not by the load balancer (the NLB is L4). oidc_client_id,
# oidc_client_secret, and oidc_scope feed that flow (see the AUTH_OIDC_* env in
# ecs.tf); the server validates API bearer tokens with oidc_issuer (issuer-only,
# audience not checked). The authorization, token, and JWKS endpoints are
# discovered from the issuer's OIDC discovery document. The owner/Unix login is
# derived from the token's email claim (no configurable principal claim).
#
# The issuer defaults to Vouch (https://vouch.sh/docs/applications/). See the
# Vouch discovery document: https://us.vouch.sh/.well-known/openid-configuration
variable "oidc_issuer" {
  description = "OIDC issuer URL"
  type        = string
  default     = "https://us.vouch.sh"
}

variable "oidc_client_id" {
  description = "Client ID of the confidential Vouch app the ALB uses for the dashboard OIDC flow (redirect URI https://<domain_name>/oauth2/idpresponse)"
  type        = string
}

variable "oidc_client_secret" {
  description = "Client secret for the dashboard Vouch app (source from a secrets backend / TF_VAR, never commit)"
  type        = string
  sensitive   = true
}

variable "oidc_scope" {
  description = "OIDC scopes to request (Vouch supports openid and email)"
  type        = string
  default     = "openid email"
}

# --- GitHub App token minting (server-owned credential) ---

variable "github_app_id" {
  description = "GitHub App ID (or Client ID) the server signs App JWTs as (DEVBOX_GITHUB_APP_ID)."
  type        = string
}

variable "github_app_key_param_name" {
  description = "Name of the SSM SecureString parameter holding the GitHub App private key, read by the server's task role to mint tokens (DEVBOX_GITHUB_KEY_PARAM)."
  type        = string
}

variable "github_app_key_param_arn" {
  description = "ARN of the GitHub App private-key SSM parameter, granted to the task role for ssm:GetParameter."
  type        = string
}

variable "agent_audience" {
  description = "Expected `aud` on agent web-identity tokens (DEVBOX_AGENT_AUDIENCE); must equal the DEVBOX_SERVER_URL the boxes use to reach the control plane."
  type        = string
}

variable "pool_role_arns" {
  description = "IAM role ARNs of warm-pool hosts, trusted as agent callers (DEVBOX_POOL_ROLE_ARNS)."
  type        = list(string)
}

variable "builder_role_arns" {
  description = "IAM role ARNs of builder hosts (snapshot-builder, image-builder) trusted as agent callers (DEVBOX_BUILDER_ROLE_ARNS)."
  type        = list(string)
  default     = []
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
