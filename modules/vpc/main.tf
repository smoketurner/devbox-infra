module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.6.1"

  name = var.name
  cidr = var.cidr

  azs             = var.azs
  private_subnets = var.private_subnets

  enable_nat_gateway   = false
  enable_dns_hostnames = var.enable_dns_hostnames
  enable_dns_support   = var.enable_dns_support

  enable_ipv6                                   = true
  private_subnet_assign_ipv6_address_on_creation = true
  private_subnet_ipv6_prefixes                   = range(length(var.private_subnets))

  tags = local.tags
}

resource "aws_security_group" "vpc_endpoints" {
  name_prefix = "${var.name}-vpce-"
  description = "Security group for VPC endpoints"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "HTTPS from VPC (IPv4)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.cidr]
  }

  ingress {
    description      = "HTTPS from VPC (IPv6)"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    ipv6_cidr_blocks = [module.vpc.vpc_ipv6_cidr_block]
  }

  tags = merge(local.tags, {
    Name = "${var.name}-vpce"
  })
}

module "vpc_endpoints" {
  source  = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"
  version = "6.6.1"

  vpc_id = module.vpc.vpc_id

  endpoints = {
    ssm = {
      service             = "ssm"
      private_dns_enabled = true
      ip_address_type     = "dualstack"
      subnet_ids          = module.vpc.private_subnets
      security_group_ids  = [aws_security_group.vpc_endpoints.id]
      tags                = { Name = "${var.name}-ssm" }
    }
    ssmmessages = {
      service             = "ssmmessages"
      private_dns_enabled = true
      ip_address_type     = "dualstack"
      subnet_ids          = module.vpc.private_subnets
      security_group_ids  = [aws_security_group.vpc_endpoints.id]
      tags                = { Name = "${var.name}-ssmmessages" }
    }
    ec2messages = {
      service             = "ec2messages"
      private_dns_enabled = true
      ip_address_type     = "dualstack"
      subnet_ids          = module.vpc.private_subnets
      security_group_ids  = [aws_security_group.vpc_endpoints.id]
      tags                = { Name = "${var.name}-ec2messages" }
    }
  }

  tags = local.tags
}
