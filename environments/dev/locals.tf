locals {
  environment = "dev"
  region      = "us-east-1"

  azs = ["us-east-1a", "us-east-1b", "us-east-1c"]

  # Workload VPC (private only, no internet access)
  vpc_cidr        = "10.0.0.0/16"
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]

  # Egress VPC (NAT gateway + future Network Firewall Proxy)
  egress_vpc_cidr         = "10.1.0.0/16"
  egress_private_subnets  = ["10.1.1.0/24", "10.1.2.0/24", "10.1.3.0/24"]
  egress_public_subnets   = ["10.1.101.0/24", "10.1.102.0/24", "10.1.103.0/24"]

  tags = {
    Environment = local.environment
    ManagedBy   = "terraform"
  }
}
