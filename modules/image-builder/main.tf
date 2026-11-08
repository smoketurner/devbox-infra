# Primary resources for the image-builder module

################################################################################
# KMS Key for AMI Encryption
################################################################################

resource "aws_kms_key" "ami" {
  description             = "Encryption key for devbox golden AMI snapshots and workspace data-volume snapshots"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms_key.json

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-ami"
  })
}

resource "aws_kms_alias" "ami" {
  name          = "alias/${local.name_prefix}-ami"
  target_key_id = aws_kms_key.ami.key_id
}

################################################################################
# Component Artifact Bucket
################################################################################

# Module-owned bucket backing the S3 component-definition path (components.tf).
# aws_imagebuilder_component takes EITHER inline `data` (hard-capped at 16000
# chars after rendering) OR a `uri` pointing at an S3 object; referencing by uri
# is now the only path, so the module provisions its own bucket rather than
# requiring a caller-supplied one. This is an S3 account regional namespace
# general-purpose bucket (bucket_namespace = "account-regional"), so its name
# is suffixed with "-an" and is scoped to this account and region: only this
# AWS account can ever create a bucket in its own account-regional namespace,
# so the name can never be squatted by another account. It stays a
# general-purpose bucket, so every companion resource below (versioning, public
# access block, SSE, lifecycle) and the Image Builder uri=s3://bucket/key read
# path are unaffected. Name is interpolated (not hardcoded) and
# lowercase/DNS-compatible as S3 requires.
resource "aws_s3_bucket" "components" {
  bucket           = "${local.name_prefix}-components-${local.aws_account_id}-${local.aws_region}-an"
  bucket_namespace = "account-regional"

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-components"
  })
}

# Versioning is on so a content-addressed overwrite (same key, new render) keeps
# the prior object version recoverable; the lifecycle rule below reaps old
# versions so they do not accumulate.
resource "aws_s3_bucket_versioning" "components" {
  bucket = aws_s3_bucket.components.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Component definitions are internal build artifacts: never public.
resource "aws_s3_bucket_public_access_block" "components" {
  bucket = aws_s3_bucket.components.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# SSE-KMS at rest reusing the module's AMI CMK (the build instance role already
# holds Encrypt/Decrypt on it). bucket_key_enabled cuts KMS request cost.
resource "aws_s3_bucket_server_side_encryption_configuration" "components" {
  bucket = aws_s3_bucket.components.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.ami.arn
    }
    bucket_key_enabled = true
  }
}

# Keys are content-addressed (components.tf): a definition change writes a NEW
# object at a new hashed key, so the real accumulation is NONCURRENT versions
# left when the same key is overwritten with identical-key content. Reap only
# those (after 7 days of recoverability) and sweep failed multipart uploads.
# Do NOT expire current object versions: the current object at each hashed key
# is the live component definition that aws_imagebuilder_component.this fetches
# by uri at build time, and a blanket current-version expiration cannot tell a
# stranded key from an in-use one, so it would delete live artifacts out from
# under an environment that has not re-applied or rebuilt in a while.
resource "aws_s3_bucket_lifecycle_configuration" "components" {
  bucket = aws_s3_bucket.components.id

  rule {
    id     = "expire-stale-components"
    status = "Enabled"

    filter {
      prefix = "image-builder/components/"
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  # Lifecycle rules act on versions, so wire the explicit dependency.
  depends_on = [aws_s3_bucket_versioning.components]
}

################################################################################
# Image Recipe
################################################################################

resource "aws_imagebuilder_image_recipe" "this" {
  name         = "${local.name_prefix}-recipe"
  parent_image = data.aws_ssm_parameter.al2023_ami.value
  version      = "1.0.21"

  dynamic "component" {
    for_each = sort(keys(local.component_map))
    content {
      component_arn = aws_imagebuilder_component.this[component.value].arn
    }
  }

  block_device_mapping {
    device_name = "/dev/xvda"

    ebs {
      delete_on_termination = true
      encrypted             = true
      kms_key_id            = aws_kms_key.ami.arn
      # Holds the OS, toolchains, and pre-pulled Docker images. Pool instances
      # launched from this AMI must set ebs_volume_size >= this value.
      volume_size = 100
      volume_type = "gp3"
    }
  }

  tags = local.tags

  lifecycle {
    create_before_destroy = true
  }
}

################################################################################
# Infrastructure Configuration
################################################################################

resource "aws_imagebuilder_infrastructure_configuration" "this" {
  name                          = "${local.name_prefix}-infra"
  description                   = "Infrastructure configuration for Image Builder build instances"
  instance_profile_name         = aws_iam_instance_profile.build_instance.name
  instance_types                = [var.build_instance_type]
  security_group_ids            = [aws_security_group.build.id]
  subnet_id                     = var.build_subnet_ids[0]
  terminate_instance_on_failure = true

  instance_metadata_options {
    http_tokens = "required"
  }

  tags = local.tags
}

################################################################################
# Distribution Configuration
################################################################################

resource "aws_imagebuilder_distribution_configuration" "this" {
  name = "${local.name_prefix}-distribution"

  # Primary region distribution
  distribution {
    region = local.aws_region

    ami_distribution_configuration {
      name       = var.ami_name_pattern
      kms_key_id = aws_kms_key.ami.arn

      ami_tags = merge(var.tags, {
        Pipeline  = "ami-image-builder"
        BuildDate = "{{imagebuilder:buildDate}}"
        SourceAMI = data.aws_ssm_parameter.al2023_ami.value
      })

      launch_permission {
        user_ids = length(var.trusted_account_ids) > 0 ? concat(
          [local.aws_account_id],
          var.trusted_account_ids
        ) : [local.aws_account_id]
      }
    }

    ssm_parameter_configuration {
      ami_account_id = local.aws_account_id
      parameter_name = var.ssm_parameter_path
      data_type      = "aws:ec2:image"
    }
  }

  # Cross-region distribution
  dynamic "distribution" {
    for_each = var.distribution_regions
    content {
      region = distribution.value

      ami_distribution_configuration {
        name       = var.ami_name_pattern
        kms_key_id = aws_kms_key.ami.arn

        ami_tags = merge(var.tags, {
          Pipeline  = "ami-image-builder"
          BuildDate = "{{imagebuilder:buildDate}}"
          SourceAMI = data.aws_ssm_parameter.al2023_ami.value
        })

        launch_permission {
          user_ids = length(var.trusted_account_ids) > 0 ? concat(
            [local.aws_account_id],
            var.trusted_account_ids
          ) : [local.aws_account_id]
        }
      }
    }
  }

  tags = local.tags
}

################################################################################
# SSM Parameter Store - Latest AMI ID
################################################################################

resource "aws_ssm_parameter" "ami_id" {
  name      = var.ssm_parameter_path
  type      = "String"
  data_type = "aws:ec2:image"
  value     = data.aws_ssm_parameter.al2023_ami.value

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-ami-latest"
  })

  lifecycle {
    ignore_changes = [value]
  }
}

################################################################################
# Image Builder Pipeline
################################################################################

resource "aws_imagebuilder_image_pipeline" "this" {
  name                             = "${local.name_prefix}-pipeline"
  description                      = "AMI build pipeline for devbox golden images"
  image_recipe_arn                 = aws_imagebuilder_image_recipe.this.arn
  infrastructure_configuration_arn = aws_imagebuilder_infrastructure_configuration.this.arn
  distribution_configuration_arn   = aws_imagebuilder_distribution_configuration.this.arn
  execution_role                   = aws_iam_role.execution.arn
  status                           = "ENABLED"
  enhanced_image_metadata_enabled  = true

  dynamic "schedule" {
    for_each = var.schedule_enabled ? [1] : []
    content {
      schedule_expression                = var.schedule_expression
      pipeline_execution_start_condition = var.pipeline_execution_start_condition
    }
  }

  image_tests_configuration {
    image_tests_enabled = true
    timeout_minutes     = var.image_tests_timeout_minutes
  }

  # Enable Amazon Inspector vulnerability scanning on images produced by this
  # pipeline. These are EC2 AMIs (not container images), so no ecr_configuration
  # is set. Scanning is service-managed; account-level Amazon Inspector EC2
  # scanning must be enabled out-of-band for findings to be generated.
  image_scanning_configuration {
    image_scanning_enabled = true
  }

  tags = local.tags
}

################################################################################
# Lifecycle Policy
################################################################################

resource "aws_imagebuilder_lifecycle_policy" "this" {
  name           = "${local.name_prefix}-lifecycle"
  description    = "Retains the 5 most recent AMI versions and deletes older ones"
  execution_role = aws_iam_role.lifecycle.arn
  resource_type  = "AMI_IMAGE"

  policy_detail {
    action {
      type = "DELETE"
      include_resources {
        amis      = true
        snapshots = true
      }
    }
    filter {
      type  = "COUNT"
      value = 5
    }
    exclusion_rules {
      tag_map = {
        "devbox:status" = "production"
        "devbox:keep"   = "true"
      }
    }
  }

  # Select AMIs to garbage-collect by the stable Pipeline tag rather than by a
  # pinned recipe semantic_version. Pinning a single recipe version meant that
  # after any recipe bump, AMIs built from older recipe versions fell outside
  # the selection and were never garbage-collected, leaking EBS snapshots over
  # time (latent snapshot sprawl). The "Pipeline = ami-image-builder" tag is
  # applied to every distributed AMI (see ami_distribution_configuration.ami_tags
  # above, primary + cross-region), so selecting on it covers AMIs across all
  # recipe versions while the retain-5 count and production/keep exclusions below
  # still protect the AMIs we want to keep.
  resource_selection {
    tag_map = {
      Pipeline = "ami-image-builder"
    }
  }

  tags = local.tags

  depends_on = [aws_iam_role_policy.lifecycle]
}
