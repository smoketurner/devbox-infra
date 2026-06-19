locals {
  environment = "dev"
  region      = "us-east-1"

  azs = slice(data.aws_availability_zones.available.names, 0, 3)

  # Workload VPC (private only, no internet access)
  vpc_cidr        = "10.0.0.0/16"
  private_subnets = [for i, az in local.azs : cidrsubnet(local.vpc_cidr, 8, i + 1)]

  # Egress VPC (NAT gateway + future Network Firewall Proxy)
  egress_vpc_cidr        = "10.1.0.0/16"
  egress_private_subnets = [for i, az in local.azs : cidrsubnet(local.egress_vpc_cidr, 8, i + 1)]
  egress_public_subnets  = [for i, az in local.azs : cidrsubnet(local.egress_vpc_cidr, 8, i + 101)]

  tags = {
    Environment = local.environment
    ManagedBy   = "terraform"
  }
}
