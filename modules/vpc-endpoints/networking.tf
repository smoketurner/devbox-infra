# Security group fronting the interface VPC endpoints. The pool SG references
# this SG as its 443 egress destination, so inbound here must admit the pool
# nodes' in-VPC addresses on 443.

resource "aws_security_group" "endpoints" {
  name        = "${local.name_prefix}-endpoints"
  description = "Security group for the workload VPC interface endpoints"
  vpc_id      = var.vpc_id

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-endpoints"
  })
}

resource "aws_vpc_security_group_ingress_rule" "https_from_vpc" {
  security_group_id = aws_security_group.endpoints.id
  description       = "Allow inbound HTTPS from in-VPC clients (pool nodes)"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = var.vpc_cidr_block

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-ingress-https"
  })
}

resource "aws_vpc_security_group_ingress_rule" "https_from_vpc_ipv6" {
  security_group_id = aws_security_group.endpoints.id
  description       = "Allow inbound HTTPS from in-VPC clients (pool nodes, IPv6)"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv6         = var.vpc_ipv6_cidr_block

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-ingress-https-ipv6"
  })
}
