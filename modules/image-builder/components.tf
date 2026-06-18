resource "aws_imagebuilder_component" "this" {
  for_each = var.component_files

  name     = "${var.name_prefix}-${each.key}-${substr(sha256(templatefile("${path.module}/components/${each.value.file}", each.value.vars)), 0, 8)}"
  platform = "Linux"
  version  = each.value.version
  data     = templatefile("${path.module}/components/${each.value.file}", each.value.vars)

  tags = merge(local.tags, {
    ComponentOrder = tostring(each.value.order)
  })
}
