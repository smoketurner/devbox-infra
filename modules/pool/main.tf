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

resource "aws_vpc_security_group_egress_rule" "https" {
  security_group_id = aws_security_group.pool.id
  description       = "Allow outbound HTTPS traffic"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-egress-https"
  })
}

################################################################################
# Launch Template
################################################################################

resource "aws_launch_template" "pool" {
  name = "${local.name_prefix}-lt"

  image_id = "resolve:ssm:${var.ssm_ami_parameter}"
  # No instance_type: the ASG's mixed-instances policy selects types by
  # attributes (vCPU/memory) below.

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

  # Spot-only, with attribute-based instance selection across many Graviton
  # types for capacity-pool diversity. capacity_rebalance proactively launches a
  # replacement on a rebalance recommendation, ahead of the hard 2-minute
  # interruption notice.
  capacity_rebalance = true

  mixed_instances_policy {
    launch_template {
      launch_template_specification {
        launch_template_id = aws_launch_template.pool.id
        version            = "$Latest"
      }

      override {
        instance_requirements {
          vcpu_count {
            min = var.vcpu_count.min
            max = var.vcpu_count.max
          }

          memory_mib {
            min = var.memory_mib.min
            max = var.memory_mib.max
          }

          cpu_manufacturers     = ["amazon-web-services"] # Graviton (arm64) only
          burstable_performance = "included"              # allow t4g
          instance_generations  = ["current"]
        }
      }
    }

    instances_distribution {
      on_demand_base_capacity                  = 0
      on_demand_percentage_above_base_capacity = 0 # 100% spot
      spot_allocation_strategy                 = "price-capacity-optimized"
    }
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
