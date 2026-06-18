locals {
  name_prefix = "${var.name_prefix}-image-builder"

  tags = merge(
    var.tags,
    {
      Pipeline    = "ami-image-builder"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  )
}
