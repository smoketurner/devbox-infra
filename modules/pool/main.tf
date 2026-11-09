# Primary resources for the pool module

################################################################################
# Security Group
################################################################################

resource "aws_security_group" "pool" {
  name        = "${local.name_prefix}-instances"
  description = "Security group for devbox pool instances"
  vpc_id      = var.vpc_id

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-instances"
  })
}

# No inbound rules: callers reach sshd over an AWS-StartSSHSession SSM tunnel
# (the agent connects to sshd on loopback), so no security group ingress is
# needed. Instances have no public IP and there is no bastion.

# Egress posture: a pool box has NO direct route to arbitrary third-party hosts
# (api.anthropic.com, crates.io, pypi.org, ...). The ONLY path to those is THROUGH
# the control-plane CONNECT egress proxy. The rules below permit exactly the direct
# traffic NO_PROXY requires — AWS service endpoints and the control-plane host —
# and nothing else. The former broad tcp/443 -> 0.0.0.0/0 (+ ::/0) and
# tcp/<proxy> -> 0.0.0.0/0 (+ ::/0) rules are intentionally gone.

# AWS services via the workload VPC's interface endpoints: the SSM tunnel
# (ssm/ssmmessages/ec2messages), the agent's STS/web-identity calls (sts), ECR
# image pulls (ecr.api/ecr.dkr + the S3 gateway endpoint), and ec2:CreateTags
# self-tagging (ec2). private_dns_enabled on those endpoints makes the box's
# NO_PROXY `.amazonaws.com` DNS resolve to the private endpoint IPs, so this stays
# on the AWS private network instead of transiting fck-nat to 0.0.0.0/0.
#
# A referenced_security_group_id egress rule is family-agnostic: it covers BOTH
# IPv4 and IPv6 traffic to the endpoints' ENIs, so no separate _ipv6 sibling is
# required here.
resource "aws_vpc_security_group_egress_rule" "aws_endpoints" {
  security_group_id            = aws_security_group.pool.id
  description                  = "Allow outbound HTTPS to the VPC interface endpoints (SSM tunnel, STS/web-identity, ECR, ec2)"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = var.endpoints_security_group_id

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-egress-aws-endpoints"
  })
}

# Control-plane host direct 443 per NO_PROXY: the API + git reverse proxy. Scoped
# to the control-plane NLB static EIP (in a separate VPC, reached over the public
# internet), not 0.0.0.0/0.
resource "aws_vpc_security_group_egress_rule" "control_plane_https" {
  security_group_id = aws_security_group.pool.id
  description       = "Allow outbound HTTPS to the control-plane host (API + git reverse proxy)"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = var.control_plane_cidr

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-egress-control-plane"
  })
}

# Dual-stack sibling, created only when a stable control-plane IPv6 CIDR is
# supplied. The NLB's IPv6 node address is auto-assigned and not exported as a
# stable value, so control_plane_ipv6_cidr defaults to "" and this rule is
# absent by default.
resource "aws_vpc_security_group_egress_rule" "control_plane_https_ipv6" {
  count = var.control_plane_ipv6_cidr != "" ? 1 : 0

  security_group_id = aws_security_group.pool.id
  description       = "Allow outbound HTTPS to the control-plane host (API + git reverse proxy, IPv6)"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv6         = var.control_plane_ipv6_cidr

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-egress-control-plane-ipv6"
  })
}

# Reach the control-plane CONNECT egress proxy — the only route to arbitrary
# third-party hosts. Tightened from 0.0.0.0/0 to the same control-plane NLB CIDR
# the proxy hostname resolves to.
resource "aws_vpc_security_group_egress_rule" "egress_proxy" {
  security_group_id = aws_security_group.pool.id
  description       = "Allow outbound to the control-plane egress proxy"
  ip_protocol       = "tcp"
  from_port         = var.egress_proxy_port
  to_port           = var.egress_proxy_port
  cidr_ipv4         = var.control_plane_cidr

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-egress-proxy"
  })
}

# Dual-stack sibling for the proxy port, created only when a control-plane IPv6
# CIDR is supplied (see control_plane_https_ipv6 for why it defaults off).
resource "aws_vpc_security_group_egress_rule" "egress_proxy_ipv6" {
  count = var.control_plane_ipv6_cidr != "" ? 1 : 0

  security_group_id = aws_security_group.pool.id
  description       = "Allow outbound to the control-plane egress proxy (IPv6)"
  ip_protocol       = "tcp"
  from_port         = var.egress_proxy_port
  to_port           = var.egress_proxy_port
  cidr_ipv6         = var.control_plane_ipv6_cidr

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-egress-proxy-ipv6"
  })
}

# Operator escape hatch: additional direct-egress /32s without a code change.
# Default empty => no rules => locked-down default posture.
resource "aws_vpc_security_group_egress_rule" "extra_direct" {
  for_each = toset(var.extra_direct_egress_cidrs)

  security_group_id = aws_security_group.pool.id
  description       = "Operator-allowed direct HTTPS egress"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = each.value

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-egress-extra-${replace(each.value, "/[./:]/", "-")}"
  })
}

resource "aws_vpc_security_group_egress_rule" "extra_direct_ipv6" {
  for_each = toset(var.extra_direct_egress_ipv6_cidrs)

  security_group_id = aws_security_group.pool.id
  description       = "Operator-allowed direct HTTPS egress (IPv6)"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv6         = each.value

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-egress-extra-ipv6-${replace(each.value, "/[./:]/", "-")}"
  })
}

################################################################################
# Launch Template
################################################################################

resource "aws_launch_template" "pool" {
  name = "${local.name_prefix}-lt"

  image_id      = "resolve:ssm:${var.ssm_ami_parameter}"
  instance_type = var.instance_type

  iam_instance_profile {
    arn = aws_iam_instance_profile.host.arn
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = var.metadata_hop_limit
    instance_metadata_tags      = "enabled"
  }

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      delete_on_termination = true
      encrypted             = var.ebs_encrypted
      volume_size           = var.ebs_volume_size
      volume_type           = "gp3"
    }
  }

  # Per-instance /workspace volume cloned from the latest workspace snapshot. EC2
  # clones an independent encrypted volume for each instance at launch and deletes
  # it on terminate. Encryption (and the CMK) is inherited from the snapshot, so
  # `encrypted`/`kms_key_id` must NOT be set here (specifying them is rejected).
  # The fs is labelled `workspace`; the AMI's workspace.mount mounts it by label.
  # Auto-attach only once the snapshot-builder has published a real snapshot id;
  # while the parameter is still the "none" placeholder, instances launch without
  # the volume and fall back to /workspace on the root volume.
  dynamic "block_device_mappings" {
    for_each = startswith(data.aws_ssm_parameter.workspace_snapshot.value, "snap-") ? [1] : []

    content {
      device_name = local.workspace_device

      ebs {
        snapshot_id           = data.aws_ssm_parameter.workspace_snapshot.value
        delete_on_termination = true
        volume_size           = var.workspace_volume_size
        volume_type           = "gp3"
      }
    }
  }

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = concat([aws_security_group.pool.id], var.security_group_ids)
  }

  tag_specifications {
    resource_type = "instance"

    tags = merge(local.tags, {
      Name = local.asg_name
    })
  }

  tag_specifications {
    resource_type = "volume"

    tags = merge(local.tags, {
      Name = "${local.asg_name}-vol"
    })
  }

  tags = local.tags
}

################################################################################
# Auto Scaling Group
################################################################################

resource "aws_autoscaling_group" "pool" {
  name = local.asg_name

  launch_template {
    id      = aws_launch_template.pool.id
    version = "$Latest"
  }

  min_size         = var.min_size
  max_size         = var.max_size
  desired_capacity = var.min_size

  vpc_zone_identifier       = var.subnet_ids
  health_check_type         = var.health_check_type
  health_check_grace_period = var.health_check_grace_period

  # The control plane (reconciler) owns desired_capacity at runtime.
  # Terraform must never revert capacity changes made by the reconciler.
  lifecycle {
    ignore_changes = [desired_capacity]
  }

  dynamic "tag" {
    for_each = merge(local.tags, { Name = local.asg_name })
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }
}
