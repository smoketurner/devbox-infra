# Primary resources for the image-builder module

################################################################################
# Image Recipe
################################################################################

resource "aws_imagebuilder_image_recipe" "this" {
  name         = "${local.name_prefix}-recipe"
  parent_image = data.aws_ssm_parameter.al2023_ami.value
  version      = "1.0.0"

  dynamic "component" {
    for_each = sort(keys(var.component_files))
    content {
      component_arn = aws_imagebuilder_component.this[component.value].arn
    }
  }

  block_device_mapping {
    device_name = "/dev/xvda"

    ebs {
      delete_on_termination = true
      encrypted             = true
      kms_key_id            = "alias/aws/ebs"
      volume_size           = 30
      volume_type           = "gp3"
    }
  }

  tags = local.tags
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
  subnet_id                     = var.egress_subnet_ids[0]
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
    region = data.aws_region.current.region

    ami_distribution_configuration {
      name       = var.ami_name_pattern
      kms_key_id = "alias/aws/ebs"

      ami_tags = {
        Environment = var.environment
        ManagedBy   = "terraform"
        Pipeline    = "ami-image-builder"
        BuildDate   = "{{imagebuilder:buildDate}}"
        SourceAMI   = "{{imagebuilder:parentImage}}"
      }

      launch_permission {
        user_ids = length(var.trusted_account_ids) > 0 ? concat(
          [data.aws_caller_identity.current.account_id],
          var.trusted_account_ids
        ) : [data.aws_caller_identity.current.account_id]
      }
    }

    ssm_parameter_configuration {
      ami_account_id = data.aws_caller_identity.current.account_id
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
        kms_key_id = "alias/aws/ebs"

        ami_tags = {
          Environment = var.environment
          ManagedBy   = "terraform"
          Pipeline    = "ami-image-builder"
          BuildDate   = "{{imagebuilder:buildDate}}"
          SourceAMI   = "{{imagebuilder:parentImage}}"
        }

        launch_permission {
          user_ids = length(var.trusted_account_ids) > 0 ? concat(
            [data.aws_caller_identity.current.account_id],
            var.trusted_account_ids
          ) : [data.aws_caller_identity.current.account_id]
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
