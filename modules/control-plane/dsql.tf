# Aurora DSQL — the production document store.
#
# The server connects over the public endpoint as the custom `db_role` with an
# IAM auth token it mints (and refreshes) at runtime; no static password. The
# role is provisioned by the bootstrap SQL (templates/bootstrap.sql.tftpl) before
# first deploy. Migrations run on startup. The connection string is built in
# locals.tf.

resource "aws_dsql_cluster" "this" {
  deletion_protection_enabled = var.dsql_deletion_protection

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-dsql"
  })
}
