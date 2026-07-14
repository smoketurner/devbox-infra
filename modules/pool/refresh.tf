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
    # StartAutomationExecution rejects an empty parameters map, and an
    # EventBridge target with no input passes the whole event as parameters —
    # so the document declares one no-op parameter for the target to pass.
    # The default keeps manual starts parameterless.
    parameters = {
      Trigger = {
        type        = "String"
        default     = "manual"
        description = "Invocation source; unused by the steps"
      }
    }
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

  # Exactly one parameter: no input passes the whole event as parameters, and
  # an empty map fails StartAutomationExecution validation. Values are string
  # lists — the shape EventBridge maps onto automation parameters.
  input = jsonencode({ Trigger = ["eventbridge"] })
}

# Workspace-snapshot rollout via launch-template re-point + ASG instance refresh
#
# Unlike the AMI (resolved through resolve:ssm in the launch template's image_id),
# the workspace snapshot id is a *literal* block-device-mapping value read by
# Terraform at plan time, so a newly published snapshot never reaches the running
# pool on its own. When the snapshot-builder updates the snapshot parameter, an
# EventBridge rule starts an SSM Automation whose script clones the launch
# template's $Latest with the new snapshot id on the workspace device, then starts
# a rolling instance refresh. Claimed hosts are scale-in protected, so the refresh
# (ScaleInProtectedInstances = Ignore) skips them and rolls only unclaimed warm
# hosts; Claimed hosts adopt the new snapshot when released and replaced. The
# script is idempotent — a no-op when $Latest already carries the snapshot.

resource "aws_ssm_document" "snapshot_refresh" {
  name            = "${local.name_prefix}-snapshot-refresh"
  document_type   = "Automation"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "0.3"
    description   = "Re-point the launch template at the latest workspace snapshot and roll unclaimed warm hosts"
    assumeRole    = aws_iam_role.snapshot_refresh_automation.arn
    # No-op parameter for the EventBridge target — see ami_refresh.
    parameters = {
      Trigger = {
        type        = "String"
        default     = "manual"
        description = "Invocation source; unused by the steps"
      }
    }
    mainSteps = [{
      name   = "repointAndRefresh"
      action = "aws:executeScript"
      isEnd  = true
      inputs = {
        Runtime = "python3.11"
        Handler = "handler"
        InputPayload = {
          LaunchTemplateId     = aws_launch_template.pool.id
          AsgName              = local.asg_name
          WorkspaceDevice      = local.workspace_device
          WorkspaceVolumeSize  = var.workspace_volume_size
          SnapshotParameter    = var.workspace_snapshot_ssm_parameter
          MinHealthyPercentage = var.ami_refresh_min_healthy_percentage
          InstanceWarmup       = var.ami_refresh_instance_warmup
        }
        Script = file("${path.module}/scripts/snapshot-refresh.py")
      }
    }]
  })

  tags = local.tags
}

resource "aws_cloudwatch_event_rule" "workspace_snapshot_published" {
  name        = "${local.name_prefix}-workspace-snapshot-published"
  description = "Roll the pool onto a new workspace snapshot when its parameter is updated"

  event_pattern = jsonencode({
    source      = ["aws.ssm"]
    detail-type = ["Parameter Store Change"]
    detail = {
      name      = [var.workspace_snapshot_ssm_parameter]
      operation = ["Create", "Update"]
    }
  })

  tags = local.tags
}

resource "aws_cloudwatch_event_target" "snapshot_refresh" {
  rule     = aws_cloudwatch_event_rule.workspace_snapshot_published.name
  arn      = "arn:${local.aws_partition}:ssm:${local.aws_region}:${local.aws_account_id}:automation-definition/${aws_ssm_document.snapshot_refresh.name}:${aws_ssm_document.snapshot_refresh.default_version}"
  role_arn = aws_iam_role.snapshot_refresh_events.arn

  # Exactly one parameter — see ami_refresh.
  input = jsonencode({ Trigger = ["eventbridge"] })
}
