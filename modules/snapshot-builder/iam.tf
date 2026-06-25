# SSM Automation execution role: drives the whole build (launch → clone/warm →
# snapshot → publish → GC → terminate).
resource "aws_iam_role" "snapshot_automation" {
  name               = "${local.name_prefix}-automation"
  assume_role_policy = data.aws_iam_policy_document.ssm_assume_role.json

  tags = local.tags
}

resource "aws_iam_role_policy" "snapshot_automation" {
  name   = "${local.name_prefix}-automation"
  role   = aws_iam_role.snapshot_automation.id
  policy = data.aws_iam_policy_document.snapshot_automation.json
}

# EventBridge role: starts the automation on schedule.
resource "aws_iam_role" "snapshot_events" {
  name               = "${local.name_prefix}-events"
  assume_role_policy = data.aws_iam_policy_document.events_assume_role.json

  tags = local.tags
}

resource "aws_iam_role_policy" "snapshot_events" {
  name   = "${local.name_prefix}-events"
  role   = aws_iam_role.snapshot_events.id
  policy = data.aws_iam_policy_document.snapshot_events.json
}

# Builder instance role + profile: SSM core (run-command reachability) plus the
# GitHub App key read and log writes.
resource "aws_iam_role" "builder_instance" {
  name               = "${local.name_prefix}-builder"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "builder_ssm_core" {
  role       = aws_iam_role.builder_instance.name
  policy_arn = data.aws_iam_policy.ssm_core.arn
}

resource "aws_iam_role_policy" "builder_instance" {
  name   = "${local.name_prefix}-builder"
  role   = aws_iam_role.builder_instance.id
  policy = data.aws_iam_policy_document.builder_instance.json
}

resource "aws_iam_instance_profile" "builder_instance" {
  name = "${local.name_prefix}-builder"
  role = aws_iam_role.builder_instance.name

  tags = local.tags
}
