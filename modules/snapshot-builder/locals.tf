locals {
  name_prefix = "${var.name_prefix}-snapshot-builder"

  # AWS context
  aws_partition  = data.aws_partition.current.partition
  aws_dns_suffix = data.aws_partition.current.dns_suffix
  aws_region     = data.aws_region.current.region
  aws_account_id = data.aws_caller_identity.current.account_id

  # Account-global EC2 Auto Scaling service-linked role. Pool ASGs clone a
  # per-instance volume from the CMK-encrypted workspace snapshot at launch, so
  # this role must be able to use the workspace key (otherwise launches fail with
  # Client.InvalidKMSKey.InvalidState).
  autoscaling_slr_arn = "arn:${local.aws_partition}:iam::${local.aws_account_id}:role/aws-service-role/autoscaling.${local.aws_dns_suffix}/AWSServiceRoleForAutoScaling"

  # SSM parameter ARNs the automation reads (AMI input) and writes (snapshot output).
  ami_parameter_arn      = "arn:${local.aws_partition}:ssm:${local.aws_region}:${local.aws_account_id}:parameter${var.ami_parameter}"
  snapshot_parameter_arn = "arn:${local.aws_partition}:ssm:${local.aws_region}:${local.aws_account_id}:parameter${var.ssm_parameter_path}"

  # Device the data volume is attached at on the builder. AL2023 on Nitro surfaces
  # it as an NVMe device, so the clone/warm script resolves it by EBS volume-id
  # serial rather than this name.
  data_device = "/dev/sdf"

  # Tag the snapshot, builder instance, and data volume so the automation, the GC
  # step, and the AutoScaling-launched pool hosts can all be reasoned about by tag.
  tags = merge(
    var.tags,
    {
      Pipeline = "workspace-snapshot-builder"
    }
  )

  # Tags rendered as the [{Key, Value}] shape the EC2 API expects in
  # TagSpecifications (the automation calls RunInstances/CreateSnapshot directly).
  base_tag_set = [for k, v in local.tags : { Key = k, Value = v }]

  instance_tag_set = concat(
    [
      { Key = "Name", Value = "${local.name_prefix}-builder" },
      { Key = "devbox:role", Value = "snapshot-builder" },
    ],
    local.base_tag_set,
  )

  snapshot_tag_set = concat(
    [
      { Key = "Name", Value = "${local.name_prefix}-workspace" },
      { Key = "devbox:role", Value = "workspace-snapshot" },
      { Key = "devbox:source-ami", Value = "{{ resolveAmi.AmiId }}" },
      { Key = "devbox:created-by", Value = "snapshot-builder" },
    ],
    local.base_tag_set,
  )
}
