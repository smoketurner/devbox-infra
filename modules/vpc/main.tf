module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.6.1"

  name = var.name
  cidr = var.cidr

  azs             = var.azs
  private_subnets = var.private_subnets

  enable_nat_gateway   = false
  enable_dns_hostnames = true
  enable_dns_support   = true

  enable_ipv6                                    = true
  create_egress_only_igw                         = false
  private_subnet_assign_ipv6_address_on_creation = true
  private_subnet_ipv6_prefixes                   = range(length(var.private_subnets))

  tags = local.tags
}
