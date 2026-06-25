resource "aws_security_group" "build" {
  name        = "${local.name_prefix}-build"
  description = "Security group for the snapshot builder instance"
  vpc_id      = var.build_vpc_id

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-build"
  })
}

resource "aws_vpc_security_group_egress_rule" "build_all_ipv4" {
  security_group_id = aws_security_group.build.id
  description       = "Allow all outbound IPv4 traffic (GitHub clone + AWS APIs)"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-build-egress-ipv4"
  })
}

resource "aws_vpc_security_group_egress_rule" "build_all_ipv6" {
  security_group_id = aws_security_group.build.id
  description       = "Allow all outbound IPv6 traffic (GitHub clone + AWS APIs)"
  ip_protocol       = "-1"
  cidr_ipv6         = "::/0"

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-build-egress-ipv6"
  })
}
