locals {
  name_prefix = "${var.name_prefix}-pool"

  # AWS context
  aws_partition  = data.aws_partition.current.partition
  aws_dns_suffix = data.aws_partition.current.dns_suffix
  aws_region     = data.aws_region.current.region
  aws_account_id = data.aws_caller_identity.current.account_id

  # Naming contract (shared with control plane)
  asg_name = "devbox-pool-${var.pool_id}"

  # Block device the workspace snapshot volume attaches at. Referenced by both the
  # launch template (where it is baked) and the snapshot-refresh automation (which
  # swaps the snapshot id on this device when a new snapshot is published).
  workspace_device = "/dev/sdb"

  tags = merge(
    var.tags,
    {
      Pool = var.pool_id
    }
  )
}
