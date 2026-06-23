locals {
  environment = "dev"
  region      = "us-east-1"

  azs = slice(data.aws_availability_zones.available.names, 0, 1)

  # Workload VPC: private subnets for the pool and image builds, public subnets
  # hosting the fck-nat instance that provides their internet egress.
  vpc_cidr        = "10.0.0.0/16"
  private_subnets = [for i, az in local.azs : cidrsubnet(local.vpc_cidr, 8, i + 1)]
  public_subnets  = [for i, az in local.azs : cidrsubnet(local.vpc_cidr, 8, i + 101)]

  # Control-plane VPC (single public subnet + IGW; the ECS tasks get public IPs
  # so they egress directly to DSQL's public endpoint and ECR, and an NLB fronts
  # them with a static EIP + TLS).
  cp_vpc_cidr       = "10.2.0.0/16"
  cp_public_subnets = [cidrsubnet(local.cp_vpc_cidr, 8, 1)]

  # Common tags applied to every resource via the provider's default_tags, and
  # passed explicitly to the modules whose tags default_tags can't reach: the
  # Image Builder AMI (created by the service) and pool EC2 instances (tagged via
  # launch-template tag_specifications / ASG propagate_at_launch).
  common_tags = {
    Application = "devbox"
    Environment = local.environment
    Terraform   = "true"
  }
}
