locals {
  name_prefix = "${var.name_prefix}-image-builder"

  # AWS context
  aws_partition  = data.aws_partition.current.partition
  aws_dns_suffix = data.aws_partition.current.dns_suffix
  aws_region     = data.aws_region.current.region
  aws_account_id = data.aws_caller_identity.current.account_id

  tags = merge(
    var.tags,
    {
      Pipeline    = "ami-image-builder"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  )
}
