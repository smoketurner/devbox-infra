# Primary resources for the vpc-endpoints module

################################################################################
# Interface endpoints
################################################################################

# One interface endpoint per AWS service the pool nodes must reach directly.
# private_dns_enabled = true overrides the public `.<service>.amazonaws.com`
# records with the endpoints' private IPs inside the VPC, so the box's existing
# NO_PROXY `.amazonaws.com` direct calls (SSM tunnel, agent STS/web-identity,
# ECR, ec2:CreateTags) transparently use these endpoints instead of transiting
# fck-nat to 0.0.0.0/0 — no on-box configuration change is needed.
resource "aws_vpc_endpoint" "interface" {
  for_each = toset(local.interface_services)

  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${local.aws_region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.subnet_ids
  security_group_ids  = [aws_security_group.endpoints.id]
  private_dns_enabled = true

  # NAT64/DNS64 is on in this VPC; keep dual-stack parity on the endpoint ENIs.
  ip_address_type = "dualstack"

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-${each.value}"
  })
}

################################################################################
# S3 gateway endpoint
################################################################################

# ECR image-layer blobs are served from S3; a gateway endpoint keeps those
# downloads on the AWS private network via the private route tables.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${local.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = var.private_route_table_ids

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-s3"
  })
}
