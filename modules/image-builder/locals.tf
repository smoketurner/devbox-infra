locals {
  name_prefix = "${var.name_prefix}-image-builder"

  # AWS context
  aws_partition  = data.aws_partition.current.partition
  aws_dns_suffix = data.aws_partition.current.dns_suffix
  aws_region     = data.aws_region.current.region
  aws_account_id = data.aws_caller_identity.current.account_id

  # Account-global EC2 Auto Scaling service-linked role. Pool ASGs launch
  # instances from CMK-encrypted AMI snapshots, so this role must be able to use
  # the AMI key (otherwise launches fail with Client.InvalidKMSKey.InvalidState).
  autoscaling_slr_arn = "arn:${local.aws_partition}:iam::${local.aws_account_id}:role/aws-service-role/autoscaling.${local.aws_dns_suffix}/AWSServiceRoleForAutoScaling"

  tags = merge(
    var.tags,
    {
      Pipeline = "ami-image-builder"
    }
  )
}
