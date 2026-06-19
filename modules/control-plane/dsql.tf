# Aurora DSQL — the production document store.
#
# The server connects over the public endpoint with an IAM admin auth token it
# mints (and refreshes) at runtime; no static password. Migrations run on
# startup. The connection string is built in locals.tf.

resource "aws_dsql_cluster" "this" {
  deletion_protection_enabled = var.dsql_deletion_protection

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-dsql"
  })
}
