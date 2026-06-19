locals {
  name_prefix = "${var.name_prefix}-control-plane"

  aws_partition  = data.aws_partition.current.partition
  aws_dns_suffix = data.aws_partition.current.dns_suffix
  aws_region     = data.aws_region.current.region
  aws_account_id = data.aws_caller_identity.current.account_id

  # Adopted ASG (naming contract shared with the pool module and reconciler).
  asg_arn = "arn:${local.aws_partition}:autoscaling:${local.aws_region}:${local.aws_account_id}:autoScalingGroup:*:autoScalingGroupName/devbox-pool-${var.pool_id}"

  # Direct (public) DSQL endpoint; the server mints an IAM admin token per
  # connection and connects over TLS (VerifyFull). See devbox-server db/dsql.rs.
  dsql_endpoint = "${aws_dsql_cluster.this.identifier}.dsql.${local.aws_region}.on.aws"
  database_url  = "postgres://admin@${local.dsql_endpoint}/postgres"

  container_image = "${aws_ecr_repository.server.repository_url}:${var.image_tag}"

  tags = merge(
    var.tags,
    {
      Component   = "control-plane"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  )
}
