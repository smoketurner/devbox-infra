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
      agent_url                 = var.devbox_agent_url
      control_plane_url         = var.control_plane_url
      egress_proxy_url          = var.egress_proxy_url
      egress_no_proxy           = var.egress_no_proxy
      warmup_fetch_timeout_secs = var.warmup_fetch_timeout_secs
      docker_images             = join(" ", var.docker_images)
      workspace_snapshot_param  = var.workspace_snapshot_param
      # Complex orchestration kept in a linted .sh file, injected verbatim (its
      # bash $${...} is not re-interpreted, so no templatefile escaping needed).
      test_workspace_mount_script = file("${path.module}/components/scripts/test-workspace-mount.sh")
      # The Nitro Sandboxes host files, injected verbatim the same way.
      nitro_sandbox_size_script = file("${path.module}/components/scripts/devbox-nitro-sandbox-size.sh")
      nitro_allocator_dropin    = file("${path.module}/components/files/nitro-enclaves-allocator-devbox.conf")
      sandboxd_unit             = file("${path.module}/components/files/devbox-sandboxd.service")
    }) : file("${path.module}/components/${f}")
  }

  # Stable S3 key per component. Embedding the content hash makes new rendered
  # content a new object, mirroring the component name-hash self-replacement
  # below. Because the key is content-addressed, a definition change writes a
  # NEW object and strands the previous hashed one; the module now OWNS the
  # bucket (aws_s3_bucket.components in main.tf) and reaps those superseded
  # objects via the lifecycle rule there, so no caller cleanup is expected.
  component_s3_keys = {
    for key, content in local.component_data :
    key => "image-builder/components/${local.name_prefix}-${key}-${substr(sha256(content), 0, 8)}.yml"
  }
}

# Upload every rendered component definition to the module-owned bucket.
# aws_imagebuilder_component references these by uri (below), which bypasses the
# 16000-char inline `data` cap that the largest components exceed.
resource "aws_s3_object" "component" {
  for_each = local.component_data

  bucket       = aws_s3_bucket.components.id
  key          = local.component_s3_keys[each.key]
  content      = each.value
  content_type = "application/x-yaml"

  tags = merge(local.tags, {
    ComponentOrder = each.key
  })
}

resource "aws_imagebuilder_component" "this" {
  for_each = local.component_data

  # Keep the content-hash suffix in the name so a content change forces a new
  # component (self-replacement).
  name     = "${local.name_prefix}-${each.key}-${substr(sha256(each.value), 0, 8)}"
  platform = "Linux"
  version  = "1.0.0"

  # uri is the only delivery path: reference the uploaded S3 object. (data and
  # uri are mutually exclusive; data stays null.)
  uri = "s3://${aws_s3_bucket.components.id}/${local.component_s3_keys[each.key]}"

  tags = merge(local.tags, {
    ComponentOrder = each.key
  })

  # The uri is assembled from string locals, so Terraform sees no implicit edge
  # to the object that backs it. Without this, the component could be created
  # before its S3 object exists (a first-apply race).
  depends_on = [aws_s3_object.component]
}
