# CloudWatch Log Group for the builder's clone/warm run-command output.
resource "aws_cloudwatch_log_group" "builds" {
  name              = "/devbox/snapshot-builder/builds"
  retention_in_days = var.log_retention_days

  tags = local.tags
}

# SNS topic for snapshot-build failure notifications.
resource "aws_sns_topic" "pipeline" {
  name = "${local.name_prefix}-notifications"

  tags = local.tags
}

resource "aws_sns_topic_policy" "pipeline" {
  arn    = aws_sns_topic.pipeline.arn
  policy = data.aws_iam_policy_document.sns_topic_policy.json
}

resource "aws_sns_topic_subscription" "email" {
  for_each = toset(var.notification_emails)

  topic_arn = aws_sns_topic.pipeline.arn
  protocol  = "email"
  endpoint  = each.value
}

# A stalled or failing pipeline lets the snapshot age past the fetch budget, so
# alarm on the build automation reaching a Failed/TimedOut terminal state.
resource "aws_cloudwatch_event_rule" "build_failed" {
  name        = "${local.name_prefix}-build-failed"
  description = "Matches Failed/TimedOut executions of the workspace snapshot-build automation"

  event_pattern = jsonencode({
    source      = ["aws.ssm"]
    detail-type = ["EC2 Automation Execution Status-change Notification"]
    detail = {
      Definition = [aws_ssm_document.snapshot_build.name]
      Status     = ["Failed", "TimedOut"]
    }
  })

  tags = local.tags
}

resource "aws_cloudwatch_event_target" "build_failed_sns" {
  rule = aws_cloudwatch_event_rule.build_failed.name
  arn  = aws_sns_topic.pipeline.arn
}
