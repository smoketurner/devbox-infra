module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.6.1"

  name = var.name
  cidr = var.cidr

  azs             = var.azs
  private_subnets = var.private_subnets
  public_subnets  = var.public_subnets

  enable_nat_gateway   = true
  single_nat_gateway   = var.single_nat_gateway
  enable_dns_hostnames = var.enable_dns_hostnames
  enable_dns_support   = var.enable_dns_support

  enable_ipv6                                    = true
  public_subnet_assign_ipv6_address_on_creation  = true
  private_subnet_assign_ipv6_address_on_creation = true
  public_subnet_ipv6_prefixes                    = range(length(var.public_subnets))
  private_subnet_ipv6_prefixes                   = range(length(var.public_subnets), length(var.public_subnets) + length(var.private_subnets))

  tags = local.tags
}

# TODO: AWS Network Firewall Proxy configuration
#
# The Network Firewall Proxy service is currently in public preview and does not
# yet have Terraform provider support. Once available, the following resources
# will be added here:
#
# 1. aws_networkfirewall_proxy_configuration - Associates the proxy with the NAT gateway
# 2. Proxy endpoints in spoke VPCs (managed via the vpc module or separately)
#
# Architecture: Centralized Proxy with Proxy Endpoints
# Reference: https://docs.aws.amazon.com/network-firewall/latest/developerguide/proxy-architecture-overview.html
#
# Spoke VPCs will configure HTTP_PROXY/HTTPS_PROXY environment variables pointing
# to the proxy FQDN, which resolves to PrivateLink interface endpoints automatically
# created in each connected VPC.
