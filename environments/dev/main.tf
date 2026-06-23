module "vpc" {
  source = "../../modules/vpc"

  name = "devbox-${local.environment}"
  cidr = local.vpc_cidr

  azs             = local.azs
  private_subnets = local.private_subnets
  public_subnets  = local.public_subnets
}

module "image_builder" {
  source = "../../modules/image-builder"

  name_prefix      = "devbox-${local.environment}"
  build_vpc_id     = module.vpc.vpc_id
  build_subnet_ids = module.vpc.private_subnets

  component_files = [
    "01-base.yml",
    "02-toolchain.yml",
    "03-repos.yml",
    "04-devbox.yml.tftpl",
    "99-validation.yml",
  ]

  tags = local.common_tags
}

module "pool" {
  source = "../../modules/pool"

  name_prefix = "devbox-${local.environment}"
  pool_id     = "default"

  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.private_subnets
  security_group_ids = []

  instance_type = "t4g.small"

  # Cap the pool: the reconciler sets desired_capacity to
  # min(claimed + POOL_TARGET_WARM_SIZE, max_size). With POOL_TARGET_WARM_SIZE=2,
  # max_size = 1 holds a single warm instance.
  max_size = 1

  # Consume the parameter name from image-builder so Terraform orders the
  # parameter's creation before the launch template's resolve:ssm reference.
  ssm_ami_parameter = module.image_builder.ssm_parameter_name

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

  # OIDC endpoints default to Vouch. The confidential dashboard app (redirect URI
  # https://<domain_name>/oauth2/idpresponse) drives the app-side login flow.
  oidc_client_id     = var.oidc_client_id
  oidc_client_secret = var.oidc_client_secret
}
