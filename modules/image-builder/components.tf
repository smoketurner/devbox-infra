locals {
  # Derive a stable key from each filename by stripping the .yml(.tftpl) suffix.
  component_map = {
    for f in var.component_files :
    trimsuffix(trimsuffix(f, ".tftpl"), ".yml") => f
  }

  # Render each component. `.tftpl` files are passed through templatefile so the
  # devbox-agent download URL and checksum come from Terraform variables; plain
  # `.yml` files (which contain bash `${VAR}` that must not be interpolated) are
  # read verbatim.
  component_data = {
    for key, f in local.component_map :
    key => endswith(f, ".tftpl") ? templatefile("${path.module}/components/${f}", {
      agent_url                  = var.devbox_agent_url
      agent_sha256               = var.devbox_agent_sha256
      github_app_id              = var.github_app_id
      github_app_installation_id = var.github_app_installation_id
      github_app_key_param       = var.github_app_key_param
      warmup_fetch_timeout_secs  = var.warmup_fetch_timeout_secs
      docker_images              = join(" ", var.docker_images)
    }) : file("${path.module}/components/${f}")
  }
}

resource "aws_imagebuilder_component" "this" {
  for_each = local.component_data

  name     = "${local.name_prefix}-${each.key}-${substr(sha256(each.value), 0, 8)}"
  platform = "Linux"
  version  = "1.0.0"
  data     = each.value

  tags = merge(local.tags, {
    ComponentOrder = each.key
  })
}
