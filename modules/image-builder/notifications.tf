# CloudWatch Log Group for Image Builder build logs
resource "aws_cloudwatch_log_group" "builds" {
  name              = "/devbox/image-builder/builds"
  retention_in_days = var.log_retention_days

  tags = local.tags
}

# SNS Topic for pipeline notifications
resource "aws_sns_topic" "pipeline" {
  name = "${local.name_prefix}-notifications"

  tags = local.tags
}

# SNS Topic Policy allowing EventBridge to publish
resource "aws_sns_topic_policy" "pipeline" {
  arn    = aws_sns_topic.pipeline.arn
  policy = data.aws_iam_policy_document.sns_topic_policy.json
}

# Email subscriptions (conditional on notification_emails being non-empty)
resource "aws_sns_topic_subscription" "email" {
  for_each = toset(var.notification_emails)

  topic_arn = aws_sns_topic.pipeline.arn
  protocol  = "email"
  endpoint  = each.value
}

# EventBridge rule matching pipeline state changes
resource "aws_cloudwatch_event_rule" "pipeline_status" {
  name        = "${local.name_prefix}-pipeline-status"
  description = "Matches Image Builder pipeline FAILED, CANCELLED, and AVAILABLE states"

  event_pattern = jsonencode({
    source      = ["aws.imagebuilder"]
    detail-type = ["EC2 Image Builder Image Status Change"]
    detail = {
      "pipeline-arn" = [aws_imagebuilder_image_pipeline.this.arn]
      state = {
        status = ["FAILED", "CANCELLED", "AVAILABLE"]
      }
    }
  })

  tags = local.tags
}

# EventBridge target routing events to the SNS topic
resource "aws_cloudwatch_event_target" "sns" {
  rule = aws_cloudwatch_event_rule.pipeline_status.name
  arn  = aws_sns_topic.pipeline.arn
}

# Release-triggered rebuild (opt-in, default OFF via release_rebuild_trigger_enabled).
#
# GitHub releases are NOT a native EventBridge source, so there is no AWS-managed
# event we can match on when a devbox-agent release lands. The Terraform-expressible
# half is this rule plus an IAM role EventBridge can assume (iam.tf) to start the
# pipeline. The other half is out-of-band: the devbox-agent repo's release.yml emits
# a CUSTOM event onto the default bus via the AWS CLI, e.g.
#
#   aws events put-events --entries '[{
#     "Source": "devbox.releases",
#     "DetailType": "devbox-agent release published",
#     "Detail": "{\"tag\":\"v1.2.3\"}"
#   }]'
#
# This rule reacts to exactly that source + detail-type and starts the pipeline so a
# fresh AMI bakes the new agent, reducing "forgot to rebuild after an agent release"
# toil. Nothing is wired into the agent repo from here; that put-events call is the
# out-of-band piece.
resource "aws_cloudwatch_event_rule" "release_rebuild" {
  count = var.release_rebuild_trigger_enabled ? 1 : 0

  name        = "${local.name_prefix}-release-rebuild"
  description = "Starts the image pipeline when a devbox-agent release custom event is published"

  event_pattern = jsonencode({
    source      = ["devbox.releases"]
    detail-type = ["devbox-agent release published"]
  })

  tags = local.tags
}

# EventBridge target: start this pipeline. role_arn is required because
# StartImagePipelineExecution is an API call EventBridge makes on our behalf, so it
# needs an assumable role (release_rebuild) scoped to just this pipeline.
resource "aws_cloudwatch_event_target" "release_rebuild" {
  count = var.release_rebuild_trigger_enabled ? 1 : 0

  rule     = aws_cloudwatch_event_rule.release_rebuild[0].name
  arn      = aws_imagebuilder_image_pipeline.this.arn
  role_arn = aws_iam_role.release_rebuild[0].arn
}
