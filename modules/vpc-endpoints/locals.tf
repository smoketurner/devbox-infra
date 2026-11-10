locals {
  name_prefix = "${var.name_prefix}-vpce"

  # AWS context. service_name uses the com.amazonaws.<region>.<svc> literal form,
  # so only the region (not the DNS suffix) is needed here.
  aws_partition = data.aws_partition.current.partition
  aws_region    = data.aws_region.current.region

  # Interface endpoints the pool nodes reach privately on 443. Each entry is a
  # `.amazonaws.com` host the box calls DIRECT (NO_PROXY `.amazonaws.com`);
  # private_dns_enabled resolves it to the endpoint ENIs. Any such host WITHOUT a
  # matching endpoint here is a direct call with no egress route once the broad
  # 443 rule is gone, so this list is the whole allow-list for direct AWS traffic.
  # Rationale:
  #   ssm + ssmmessages + ec2messages -> the AWS-StartSSHSession SSM tunnel, the
  #     only way callers reach sshd (the pool SG has no ingress).
  #   sts                             -> the agent's sts:GetWebIdentityToken /
  #     assume-role web-identity calls.
  #   ecr.api + ecr.dkr               -> ECR image pulls (layer blobs come from S3
  #     via the gateway endpoint below).
  #   ec2                             -> the warm-up agent's ec2:CreateTags self-tag.
  #   logs + monitoring               -> the amazon-cloudwatch-agent the AMI
  #     installs and enables (modules/image-builder/components/04-agents.yml)
  #     pushes to logs.<region>/monitoring.<region>.amazonaws.com on 443; without
  #     these endpoints that host observability egress is silently black-holed.
  interface_services = ["ssm", "ssmmessages", "ec2messages", "ecr.api", "ecr.dkr", "sts", "ec2", "logs", "monitoring"]

  tags = merge(var.tags, {
    Module = "vpc-endpoints"
  })
}
