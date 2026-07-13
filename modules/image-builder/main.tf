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
# Image Recipe
################################################################################

resource "aws_imagebuilder_image_recipe" "this" {
  name         = "${local.name_prefix}-recipe"
  parent_image = data.aws_ssm_parameter.al2023_ami.value
  version      = "1.0.16"

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

  resource_selection {
    recipe {
      name             = aws_imagebuilder_image_recipe.this.name
      semantic_version = aws_imagebuilder_image_recipe.this.version
    }
  }

  tags = local.tags

  depends_on = [aws_iam_role_policy.lifecycle]
}
