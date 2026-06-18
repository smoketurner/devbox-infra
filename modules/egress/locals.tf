locals {
  tags = merge(
    var.tags,
    {
      Module = "egress"
    }
  )
}
