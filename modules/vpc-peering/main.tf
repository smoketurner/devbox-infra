# VPC Peering Connection
#
# Temporary module to enable egress from the workload VPC through the egress VPC's
# NAT gateway via VPC peering. This will be replaced by Transit Gateway or Network
# Firewall Proxy when available.

resource "aws_vpc_peering_connection" "this" {
  vpc_id      = var.requester_vpc_id
  peer_vpc_id = var.accepter_vpc_id
  auto_accept = true

  requester {
    allow_remote_vpc_dns_resolution = true
  }

  accepter {
    allow_remote_vpc_dns_resolution = true
  }

  tags = merge(local.tags, {
    Name = var.name
  })
}

# Routes in the workload VPC pointing to the egress VPC for internet-bound traffic
# Default route (0.0.0.0/0) goes through the peering connection to reach the NAT gateway
resource "aws_route" "requester_to_accepter_ipv4" {
  count = length(var.requester_route_table_ids)

  route_table_id            = var.requester_route_table_ids[count.index]
  destination_cidr_block    = "0.0.0.0/0"
  vpc_peering_connection_id = aws_vpc_peering_connection.this.id
}

# IPv6 default route (::/0) also goes through peering — the workload VPC has no
# egress-only internet gateway; all egress is centralized in the egress VPC.
resource "aws_route" "requester_to_accepter_ipv6" {
  count = var.enable_ipv6 ? length(var.requester_route_table_ids) : 0

  route_table_id              = var.requester_route_table_ids[count.index]
  destination_ipv6_cidr_block = "::/0"
  vpc_peering_connection_id   = aws_vpc_peering_connection.this.id
}

# NAT64: 64:ff9b::/96 allows IPv6-only clients to reach IPv4 destinations
# via the egress VPC's NAT gateway performing NAT64 translation.
resource "aws_route" "requester_nat64" {
  count = var.enable_ipv6 ? length(var.requester_route_table_ids) : 0

  route_table_id              = var.requester_route_table_ids[count.index]
  destination_ipv6_cidr_block = "64:ff9b::/96"
  vpc_peering_connection_id   = aws_vpc_peering_connection.this.id
}

# Routes in the egress VPC pointing back to the workload VPC for return traffic
resource "aws_route" "accepter_to_requester_ipv4" {
  count = length(var.accepter_route_table_ids)

  route_table_id            = var.accepter_route_table_ids[count.index]
  destination_cidr_block    = var.requester_cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.this.id
}

resource "aws_route" "accepter_to_requester_ipv6" {
  count = var.enable_ipv6 ? length(var.accepter_route_table_ids) : 0

  route_table_id              = var.accepter_route_table_ids[count.index]
  destination_ipv6_cidr_block = var.requester_ipv6_cidr_block
  vpc_peering_connection_id   = aws_vpc_peering_connection.this.id
}
