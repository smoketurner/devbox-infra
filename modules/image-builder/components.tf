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
    }) : file("${path.module}/components/${f}")
  }

  # Opt-in S3-backed component path. aws_imagebuilder_component accepts EITHER
  # inline `data` (hard-capped at 16000 chars after rendering) OR a `uri` that
  # points at an S3 object; they are mutually exclusive. When enabled we upload
  # each rendered definition to S3 and reference it by uri, letting the largest
  # components exceed the inline cap. Stays dormant unless BOTH the flag is set
  # and a bucket arn is provided (the module does not provision a bucket).
  s3_components_active = var.s3_components_enabled && var.s3_bucket_arn != ""

  # Bucket name is the last ':' segment of arn:aws:s3:::bucket-name. Only used
  # when the S3 path is active.
  s3_components_bucket = local.s3_components_active ? element(split(":", var.s3_bucket_arn), length(split(":", var.s3_bucket_arn)) - 1) : ""

  # Stable S3 key per component. Embedding the content hash makes new rendered
  # content a new object, mirroring the inline name-hash self-replacement below.
  #
  # CLEANUP EXPECTATION: because the key is content-addressed, a definition
  # change writes a NEW object and leaves the previous hashed object in place
  # (Terraform no longer tracks the old key). These superseded objects are inert
  # but accumulate. The module does not own the caller-supplied bucket, so it
  # deliberately does not manage its lifecycle config here (that would risk
  # clobbering the caller's existing rules). Operators enabling S3 mode should
  # add an S3 lifecycle expiration rule on the "image-builder/components/" prefix
  # to reap stale definitions.
  component_s3_keys = {
    for key, content in local.component_data :
    key => "image-builder/components/${local.name_prefix}-${key}-${substr(sha256(content), 0, 8)}.yml"
  }
}

# Uploaded only when the S3 path is active; for_each resolves to an empty map
# otherwise so no objects are planned by default (inline path untouched).
resource "aws_s3_object" "component" {
  for_each = local.s3_components_active ? local.component_data : {}

  bucket       = local.s3_components_bucket
  key          = local.component_s3_keys[each.key]
  content      = each.value
  content_type = "application/x-yaml"

  tags = merge(local.tags, {
    ComponentOrder = each.key
  })
}

resource "aws_imagebuilder_component" "this" {
  for_each = local.component_data

  # Keep the content-hash suffix in BOTH modes so a content change forces a new
  # component (self-replacement), regardless of inline vs S3 delivery.
  name     = "${local.name_prefix}-${each.key}-${substr(sha256(each.value), 0, 8)}"
  platform = "Linux"
  version  = "1.0.0"

  # Exactly one of data/uri is non-null. Default = inline data; when the S3 path
  # is active, reference the uploaded object instead.
  data = local.s3_components_active ? null : each.value
  uri  = local.s3_components_active ? "s3://${local.s3_components_bucket}/${local.component_s3_keys[each.key]}" : null

  tags = merge(local.tags, {
    ComponentOrder = each.key
  })

  # The uri is assembled from string locals, so Terraform sees no implicit edge
  # to the object that backs it. Without this, the component could be created
  # before its S3 object exists (a first-apply race in S3 mode). The depends_on
  # is inert in inline mode where aws_s3_object.component plans to zero.
  depends_on = [aws_s3_object.component]
}
