locals {
  tags = merge(
    var.tags,
    {
      Module = "egress"
    }
  )

  # VPC endpoints to create — private_dns_enabled is false because we manage
  # DNS via Route 53 private hosted zones associated with spoke VPCs
  endpoints = {
    ssm = {
      service = "ssm"
      phz     = "ssm.us-east-1.amazonaws.com"
    }
    ssmmessages = {
      service = "ssmmessages"
      phz     = "ssmmessages.us-east-1.amazonaws.com"
    }
    ec2messages = {
      service = "ec2messages"
      phz     = "ec2messages.us-east-1.amazonaws.com"
    }
  }
}
