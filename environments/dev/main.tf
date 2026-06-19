module "vpc" {
  source = "../../modules/vpc"

  name = "devbox-${local.environment}"
  cidr = local.vpc_cidr

  azs             = local.azs
  private_subnets = local.private_subnets

  tags = local.tags
}

module "egress" {
  source = "../../modules/egress"

  name = "devbox-${local.environment}-egress"
  cidr = local.egress_vpc_cidr

  azs             = local.azs
  private_subnets = local.egress_private_subnets
  public_subnets  = local.egress_public_subnets

  single_nat_gateway = true

  # Associate VPC endpoints with the workload VPC for shared DNS resolution
  associated_vpc_ids   = { workload = module.vpc.vpc_id }
  associated_vpc_cidrs = [local.vpc_cidr]

  tags = local.tags
}

module "image_builder" {
  source = "../../modules/image-builder"

  name_prefix       = "devbox-${local.environment}"
  environment       = local.environment
  egress_vpc_id     = module.egress.vpc_id
  egress_subnet_ids = module.egress.private_subnets

  component_files = [
    "01-base.yml",
    "02-toolchain.yml",
    "03-repos.yml",
    "04-devbox.yml.tftpl",
    "99-validation.yml",
  ]

  tags = local.tags
}

# Temporary: VPC peering to allow workload VPC egress through the egress VPC's NAT gateway.
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

  tags = local.tags
}

module "pool" {
  source = "../../modules/pool"

  name_prefix = "devbox-${local.environment}"
  environment = local.environment
  pool_id     = "default"

  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.private_subnets
  security_group_ids = []

  tags = local.tags
}
