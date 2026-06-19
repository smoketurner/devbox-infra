# AMI rotation via ASG instance refresh
#
# When the AMI pipeline publishes a new image (updates var.ssm_ami_parameter),
# an EventBridge rule starts an SSM Automation that triggers a rolling ASG
# instance refresh. Because Claimed instances are scale-in protected by the
# control plane, the refresh skips them (ScaleInProtectedInstances = Ignore) and
# only replaces unclaimed warm hosts; Claimed hosts adopt the new AMI naturally
# when released and replaced. The Launch Template resolves the AMI from SSM, so
# replacements come up on the new image with no template change.

resource "aws_ssm_document" "ami_refresh" {
  name            = "${local.name_prefix}-ami-refresh"
  document_type   = "Automation"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "0.3"
    description   = "Roll unclaimed warm devbox hosts onto the latest AMI via an ASG instance refresh"
    assumeRole    = aws_iam_role.ami_refresh_automation.arn
    mainSteps = [{
      name   = "startInstanceRefresh"
      action = "aws:executeAwsApi"
      isEnd  = true
      inputs = {
        Service              = "autoscaling"
        Api                  = "StartInstanceRefresh"
        AutoScalingGroupName = local.asg_name
        Strategy             = "Rolling"
        Preferences = {
          MinHealthyPercentage      = var.ami_refresh_min_healthy_percentage
          InstanceWarmup            = var.ami_refresh_instance_warmup
          ScaleInProtectedInstances = "Ignore"
          StandbyInstances          = "Ignore"
        }
      }
    }]
  })

  tags = local.tags
}

resource "aws_cloudwatch_event_rule" "ami_published" {
  name        = "${local.name_prefix}-ami-published"
  description = "Start an ASG instance refresh when the devbox AMI parameter is updated"

  event_pattern = jsonencode({
    source      = ["aws.ssm"]
    detail-type = ["Parameter Store Change"]
    detail = {
      name      = [var.ssm_ami_parameter]
      operation = ["Create", "Update"]
    }
  })

  tags = local.tags
}

resource "aws_cloudwatch_event_target" "ami_refresh" {
  rule     = aws_cloudwatch_event_rule.ami_published.name
  arn      = "arn:${local.aws_partition}:ssm:${local.aws_region}:${local.aws_account_id}:automation-definition/${aws_ssm_document.ami_refresh.name}:${aws_ssm_document.ami_refresh.default_version}"
  role_arn = aws_iam_role.ami_refresh_events.arn
}
