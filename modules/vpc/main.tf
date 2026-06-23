module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.6.1"

  name = var.name
  cidr = var.cidr

  azs             = var.azs
  private_subnets = var.private_subnets
  public_subnets  = var.public_subnets

  # NAT is provided by a fck-nat instance (see module "fck_nat" below) instead of
  # a managed NAT gateway. Public subnets get the IGW the module creates for them.
  enable_nat_gateway   = false
  enable_dns_hostnames = true
  enable_dns_support   = true

  # Enable NAT64/DNS64 so IPv6-only clients can reach IPv4 destinations.
  private_subnet_enable_dns64 = true

  # Private subnet IPv6 prefixes are kept first to preserve existing assignments;
  # public subnets take the higher prefixes.
  enable_ipv6                                    = true
  private_subnet_assign_ipv6_address_on_creation = true
  public_subnet_assign_ipv6_address_on_creation  = true
  private_subnet_ipv6_prefixes                   = range(length(var.private_subnets))
  public_subnet_ipv6_prefixes                    = range(length(var.private_subnets), length(var.private_subnets) + length(var.public_subnets))

  tags = local.tags
}

################################################################################
# NAT instance (fck-nat)
#
# Low-cost NAT instance in the first public subnet, run in HA mode (single
# instance in a self-healing ASG). fck-nat wires the IPv4 default route
# (0.0.0.0/0) and, with NAT64 enabled, the NAT64 route (64:ff9b::/96) into every
# private route table, pointing at its ENI. IPv6 egress uses the egress-only IGW
# the vpc module creates.
################################################################################

resource "aws_security_group" "fck_nat" {
  name_prefix = "${var.name}-fck-nat-"
  description = "Allow NAT traffic from within the VPC"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "All from VPC (IPv4)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.cidr]
  }

  ingress {
    description      = "All from VPC (IPv6, for NAT64)"
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    ipv6_cidr_blocks = [module.vpc.vpc_ipv6_cidr_block]
  }

  egress {
    description      = "Allow all outbound"
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = merge(local.tags, {
    Name = "${var.name}-fck-nat"
  })
}

module "fck_nat" {
  source  = "RaJiska/fck-nat/aws"
  version = "1.6.0"

  name      = var.name
  vpc_id    = module.vpc.vpc_id
  subnet_id = module.vpc.public_subnets[0]

  ha_mode       = true
  instance_type = var.nat_instance_type
  use_nat64     = true

  update_route_tables = true
  route_tables_ids    = { for idx, rt in module.vpc.private_route_table_ids : "private-${idx}" => rt }
  route_tables6_ids   = { for idx, rt in module.vpc.private_route_table_ids : "private-${idx}" => rt }

  use_default_security_group    = false
  additional_security_group_ids = [aws_security_group.fck_nat.id]

  tags = local.tags
}
