module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.6.1"

  name = var.name
  cidr = var.cidr

  azs             = var.azs
  private_subnets = var.private_subnets
  public_subnets  = var.public_subnets

  # NAT is provided by a fck-nat instance (see module "fck_nat" below) instead of
  # a managed NAT gateway.
  enable_nat_gateway   = false
  enable_dns_hostnames = true
  enable_dns_support   = true

  # Enable NAT64/DNS64 so IPv6-only clients can reach IPv4 destinations
  private_subnet_enable_dns64 = true

  enable_ipv6                                    = true
  public_subnet_assign_ipv6_address_on_creation  = true
  private_subnet_assign_ipv6_address_on_creation = true
  public_subnet_ipv6_prefixes                    = range(length(var.public_subnets))
  private_subnet_ipv6_prefixes                   = range(length(var.public_subnets), length(var.public_subnets) + length(var.private_subnets))

  tags = local.tags
}

################################################################################
# NAT instance (fck-nat)
#
# Replaces the managed NAT gateway with a low-cost fck-nat instance. Runs in
# HA mode (single instance in an ASG that self-heals) in the first public
# subnet. fck-nat wires the IPv4 default route (0.0.0.0/0) and, with NAT64
# enabled, the NAT64 route (64:ff9b::/96) into every private route table,
# pointing at its ENI. IPv6 internet egress continues to use the egress-only
# internet gateway created by the vpc module.
################################################################################

resource "aws_security_group" "fck_nat" {
  name_prefix = "${var.name}-fck-nat-"
  description = "Allow NAT traffic from egress and peered VPCs"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "All from egress VPC (IPv4)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.cidr]
  }

  ingress {
    description      = "All from egress VPC (IPv6, for NAT64)"
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    ipv6_cidr_blocks = [module.vpc.vpc_ipv6_cidr_block]
  }

  # Workload traffic arrives over VPC peering with its original source IPs, so
  # the NAT instance must explicitly allow the peered workload CIDRs (a managed
  # NAT gateway had no security group and accepted this implicitly).
  dynamic "ingress" {
    for_each = var.associated_vpc_cidrs
    content {
      description = "All from peered VPC"
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = [ingress.value]
    }
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

# TODO: AWS Network Firewall Proxy configuration
#
# The Network Firewall Proxy service is currently in public preview and does not
# yet have Terraform provider support. Once available, the following resources
# will be added here:
#
# 1. aws_networkfirewall_proxy_configuration - Associates the proxy with the NAT instance
# 2. Proxy endpoints in spoke VPCs (managed via the vpc module or separately)
#
# Architecture: Centralized Proxy with Proxy Endpoints
# Reference: https://docs.aws.amazon.com/network-firewall/latest/developerguide/proxy-architecture-overview.html
#
# Spoke VPCs will configure HTTP_PROXY/HTTPS_PROXY environment variables pointing
# to the proxy FQDN, which resolves to PrivateLink interface endpoints automatically
# created in each connected VPC.

################################################################################
# VPC Endpoints (centralized)
################################################################################

resource "aws_security_group" "vpc_endpoints" {
  name_prefix = "${var.name}-vpce-"
  description = "Security group for VPC endpoints"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "HTTPS from egress VPC (IPv4)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.cidr]
  }

  ingress {
    description      = "HTTPS from egress VPC (IPv6)"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    ipv6_cidr_blocks = [module.vpc.vpc_ipv6_cidr_block]
  }

  # Allow HTTPS from peered workload VPCs
  dynamic "ingress" {
    for_each = var.associated_vpc_cidrs
    content {
      description = "HTTPS from peered VPC"
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }

  tags = merge(local.tags, {
    Name = "${var.name}-vpce"
  })
}

resource "aws_vpc_endpoint" "this" {
  for_each = local.endpoints

  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.us-east-1.${each.value.service}"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = false
  subnet_ids          = module.vpc.private_subnets
  security_group_ids  = [aws_security_group.vpc_endpoints.id]

  tags = merge(local.tags, {
    Name = "${var.name}-${each.key}"
  })
}

################################################################################
# Private Hosted Zones for endpoint DNS
#
# Each endpoint gets a PHZ associated with both the egress VPC and all spoke VPCs.
# Alias records point to the endpoint's regional DNS name.
################################################################################

resource "aws_route53_zone" "endpoint" {
  for_each = local.endpoints

  name = each.value.phz

  vpc {
    vpc_id = module.vpc.vpc_id
  }

  # Prevent Terraform from trying to manage VPC associations inline
  # (we handle additional associations via aws_route53_zone_association)
  lifecycle {
    ignore_changes = [vpc]
  }

  tags = merge(local.tags, {
    Name = "${var.name}-${each.key}-phz"
  })
}

resource "aws_route53_zone_association" "spoke" {
  for_each = { for pair in setproduct(keys(local.endpoints), keys(var.associated_vpc_ids)) :
    "${pair[0]}-${pair[1]}" => {
      endpoint = pair[0]
      vpc_id   = var.associated_vpc_ids[pair[1]]
    }
  }

  zone_id = aws_route53_zone.endpoint[each.value.endpoint].zone_id
  vpc_id  = each.value.vpc_id
}

resource "aws_route53_record" "endpoint" {
  for_each = local.endpoints

  zone_id = aws_route53_zone.endpoint[each.key].zone_id
  name    = each.value.phz
  type    = "A"

  alias {
    name                   = aws_vpc_endpoint.this[each.key].dns_entry[0].dns_name
    zone_id                = aws_vpc_endpoint.this[each.key].dns_entry[0].hosted_zone_id
    evaluate_target_health = true
  }
}
