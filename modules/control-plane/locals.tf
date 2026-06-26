locals {
  name_prefix = "${var.name_prefix}-control-plane"

  aws_partition  = data.aws_partition.current.partition
  aws_dns_suffix = data.aws_partition.current.dns_suffix
  aws_region     = data.aws_region.current.region
  aws_account_id = data.aws_caller_identity.current.account_id

  # Adopted ASG (naming contract shared with the pool module and reconciler).
  asg_name = "devbox-pool-${var.pool_id}"
  asg_arn  = "arn:${local.aws_partition}:autoscaling:${local.aws_region}:${local.aws_account_id}:autoScalingGroup:*:autoScalingGroupName/${local.asg_name}"

  # Dedicated least-privilege DSQL role the app authenticates as via IAM
  # (dsql:DbConnect). Created by the bootstrap SQL (see templates/bootstrap.sql.tftpl);
  # the role name doubles as its owned schema, which the default search_path
  # ("$user", public) routes unqualified objects into.
  db_role = "devbox"

  # DSQL public endpoint; the task (public IP, direct IGW egress) reaches it and
  # mints an IAM token for db_role per connection over TLS (VerifyFull). See
  # devbox-server db/dsql.rs.
  dsql_endpoint = "${aws_dsql_cluster.this.identifier}.dsql.${local.aws_region}.on.aws"
  database_url  = "postgres://${local.db_role}@${local.dsql_endpoint}/postgres"

  container_image = "${aws_ecr_repository.server.repository_url}:${var.image_tag}"

  tags = merge(
    var.tags,
    {
      Component = "control-plane"
    }
  )
}
