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
