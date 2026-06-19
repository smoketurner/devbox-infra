# Host (instance) IAM Role
#
# Attached to pool instances via the Launch Template. Grants exactly what the
# on-host devbox-agent needs: SSM core (so callers reach sshd over an SSM tunnel)
# and ec2:CreateTags to self-tag devbox:ready=true once warmed. Reading the
# devbox:owner tag for SSH authorization uses IMDS and needs no IAM.

resource "aws_iam_role" "host" {
  name               = "${local.name_prefix}-host"
  assume_role_policy = data.aws_iam_policy_document.host_assume_role.json

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "host_ssm" {
  role       = aws_iam_role.host.name
  policy_arn = data.aws_iam_policy.ssm_core.arn
}

resource "aws_iam_role_policy" "host_runtime" {
  name   = "${local.name_prefix}-host-runtime"
  role   = aws_iam_role.host.id
  policy = data.aws_iam_policy_document.host_runtime.json
}

resource "aws_iam_instance_profile" "host" {
  name = "${local.name_prefix}-host"
  role = aws_iam_role.host.name

  tags = local.tags
}

# AMI-refresh executor IAM
#
# Two roles: the SSM Automation execution role (starts the instance refresh) and
# the EventBridge role (starts the automation when a new AMI is published).

resource "aws_iam_role" "ami_refresh_automation" {
  name               = "${local.name_prefix}-ami-refresh"
  assume_role_policy = data.aws_iam_policy_document.ssm_assume_role.json

  tags = local.tags
}

resource "aws_iam_role_policy" "ami_refresh_automation" {
  name   = "${local.name_prefix}-ami-refresh"
  role   = aws_iam_role.ami_refresh_automation.id
  policy = data.aws_iam_policy_document.ami_refresh_automation.json
}

resource "aws_iam_role" "ami_refresh_events" {
  name               = "${local.name_prefix}-ami-refresh-events"
  assume_role_policy = data.aws_iam_policy_document.events_assume_role.json

  tags = local.tags
}

resource "aws_iam_role_policy" "ami_refresh_events" {
  name   = "${local.name_prefix}-ami-refresh-events"
  role   = aws_iam_role.ami_refresh_events.id
  policy = data.aws_iam_policy_document.ami_refresh_events.json
}

# The control-plane runtime identity lives in the `control-plane` module (the
# Fargate task role); there is no EC2-hosted control plane here.
