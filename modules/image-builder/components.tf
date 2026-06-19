locals {
  # Derive a stable key from each filename by stripping the .yml extension
  component_map = { for f in var.component_files : trimsuffix(f, ".yml") => f }
}

resource "aws_imagebuilder_component" "this" {
  for_each = local.component_map

  name     = "${local.name_prefix}-${each.key}-${substr(sha256(file("${path.module}/components/${each.value}")), 0, 8)}"
  platform = "Linux"
  version  = "1.0.0"
  data     = file("${path.module}/components/${each.value}")

  tags = merge(local.tags, {
    ComponentOrder = each.key
  })
}
