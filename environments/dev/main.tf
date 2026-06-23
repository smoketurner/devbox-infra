module "vpc" {
  source = "../../modules/vpc"

  name = "devbox-${local.environment}"
  cidr = local.vpc_cidr

  azs             = local.azs
  private_subnets = local.private_subnets
}

module "egress" {
  source = "../../modules/egress"

  name = "devbox-${local.environment}-egress"
  cidr = local.egress_vpc_cidr

  azs             = local.azs
  private_subnets = local.egress_private_subnets
  public_subnets  = local.egress_public_subnets

  # Associate VPC endpoints with the workload VPC for shared DNS resolution
  associated_vpc_ids   = { workload = module.vpc.vpc_id }
  associated_vpc_cidrs = [local.vpc_cidr]
}

module "image_builder" {
  source = "../../modules/image-builder"

  name_prefix       = "devbox-${local.environment}"
  egress_vpc_id     = module.egress.vpc_id
  egress_subnet_ids = module.egress.private_subnets

  component_files = [
    "01-base.yml",
    "02-toolchain.yml",
    "03-repos.yml",
    "04-devbox.yml.tftpl",
    "99-validation.yml",
  ]

  tags = local.common_tags
}

# Temporary: VPC peering to allow workload VPC egress through the egress VPC's NAT instance.
# This will be replaced by Transit Gateway or Network Firewall Proxy endpoints.
module "vpc_peering" {
  source = "../../modules/vpc-peering"

  name = "devbox-${local.environment}-workload-to-egress"

  requester_vpc_id          = module.vpc.vpc_id
  requester_cidr_block      = module.vpc.vpc_cidr_block
  requester_ipv6_cidr_block = module.vpc.vpc_ipv6_cidr_block
  requester_route_table_ids = module.vpc.private_route_table_ids

  accepter_vpc_id          = module.egress.vpc_id
  accepter_cidr_block      = module.egress.vpc_cidr_block
  accepter_ipv6_cidr_block = module.egress.vpc_ipv6_cidr_block
  accepter_route_table_ids = module.egress.private_route_table_ids
}

module "pool" {
  source = "../../modules/pool"

  name_prefix = "devbox-${local.environment}"
  pool_id     = "default"

  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.private_subnets
  security_group_ids = []

  tags = local.common_tags
}

# Dedicated control-plane VPC: a single public subnet with an internet gateway.
# The ECS tasks run here with public IPs (direct egress to DSQL's public endpoint
# and ECR), fronted by an NLB. Kept separate from the egress VPC, whose proxy/NAT
# is built for 443-only controlled egress and black-holes the DSQL 5432 path.
module "control_plane_vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.6.1"

  name = "devbox-${local.environment}-control-plane"
  cidr = local.cp_vpc_cidr

  azs            = [local.azs[0]]
  public_subnets = local.cp_public_subnets

  enable_nat_gateway      = false
  enable_dns_hostnames    = true
  enable_dns_support      = true
  map_public_ip_on_launch = true
}

# Control plane: Aurora DSQL + devbox-server on ECS/Fargate. The tasks run in the
# control-plane VPC's public subnet with public IPs and reach DSQL's public
# endpoint directly; an internet-facing NLB (static EIP + TLS) fronts them.
module "control_plane" {
  source = "../../modules/control-plane"

  name_prefix = "devbox-${local.environment}"

  vpc_id        = module.control_plane_vpc.vpc_id
  subnet_ids    = module.control_plane_vpc.public_subnets
  ingress_cidrs = ["0.0.0.0/0"]

  pool_id = "default"

  # Terraform issues the ACM cert and Route 53 alias for this hostname.
  domain_name     = var.domain_name
  route53_zone_id = aws_route53_zone.devbox_farm.zone_id

  # GitHub Actions pushes images + deploys via this OIDC-federated role.
  github_repository = "smoketurner/devbox"

  # OIDC endpoints default to Vouch. Register two apps: a confidential dashboard app
  # (redirect URI https://<domain_name>/oauth2/idpresponse) for the ALB, and a public
  # CLI app (device-code) whose client ID the server validates API tokens against.
  oidc_client_id     = var.oidc_client_id
  oidc_client_secret = var.oidc_client_secret
  cli_client_id      = var.cli_client_id
}
