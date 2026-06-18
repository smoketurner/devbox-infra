resource "aws_security_group" "build" {
  name        = "${local.name_prefix}-build"
  description = "Security group for Image Builder build instances"
  vpc_id      = var.egress_vpc_id

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-build"
  })
}

resource "aws_vpc_security_group_egress_rule" "build_all_ipv4" {
  security_group_id = aws_security_group.build.id
  description       = "Allow all outbound IPv4 traffic for package downloads"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-build-egress-ipv4"
  })
}

resource "aws_vpc_security_group_egress_rule" "build_all_ipv6" {
  security_group_id = aws_security_group.build.id
  description       = "Allow all outbound IPv6 traffic for package downloads"
  ip_protocol       = "-1"
  cidr_ipv6         = "::/0"

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-build-egress-ipv6"
  })
}

resource "aws_vpc_security_group_ingress_rule" "build_self" {
  security_group_id            = aws_security_group.build.id
  description                  = "Allow inbound traffic from other build instances for multi-instance test scenarios"
  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.build.id

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-build-ingress-self"
  })
}
