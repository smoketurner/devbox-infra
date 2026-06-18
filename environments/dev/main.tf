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

  tags = local.tags
}
