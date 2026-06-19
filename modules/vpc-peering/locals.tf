locals {
  tags = merge(
    var.tags,
    {
      Module = "vpc-peering"
    }
  )
}
