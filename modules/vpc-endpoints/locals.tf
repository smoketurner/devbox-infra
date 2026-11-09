locals {
  name_prefix = "${var.name_prefix}-vpce"

  # AWS context
  aws_partition  = data.aws_partition.current.partition
  aws_region     = data.aws_region.current.region
  aws_dns_suffix = data.aws_partition.current.dns_suffix

  # Interface endpoints the pool nodes reach privately on 443. Rationale:
  #   ssm + ssmmessages + ec2messages -> the AWS-StartSSHSession SSM tunnel, the
  #     only way callers reach sshd (the pool SG has no ingress).
  #   sts                             -> the agent's sts:GetWebIdentityToken /
  #     assume-role web-identity calls.
  #   ecr.api + ecr.dkr               -> ECR image pulls (layer blobs come from S3
  #     via the gateway endpoint below).
  #   ec2                             -> the warm-up agent's ec2:CreateTags self-tag.
  interface_services = ["ssm", "ssmmessages", "ec2messages", "ecr.api", "ecr.dkr", "sts", "ec2"]

  tags = merge(var.tags, {
    Module = "vpc-endpoints"
  })
}
