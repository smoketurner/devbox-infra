# Host (instance) IAM Role
#
# Attached to pool instances via the Launch Template. Grants exactly what the
# on-host devbox-agent needs: SSM core (so callers reach sshd over an SSM tunnel)
# and completion of the instance's own warm-up lifecycle hook. Reading the
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

# Control Plane IAM Role
#
# Provides least-privilege permissions for the devbox control plane (reconciler).
# The role allows only runtime operations: describe ASG, set capacity, manage
# instance protection, complete lifecycle actions, and tag instances.
# It explicitly excludes all Create*/Update* infrastructure permissions.

resource "aws_iam_role" "control_plane" {
  name               = "${local.name_prefix}-control-plane"
  assume_role_policy = data.aws_iam_policy_document.control_plane_assume_role.json

  tags = local.tags
}

resource "aws_iam_role_policy" "control_plane_runtime" {
  name = "${local.name_prefix}-runtime"
  role = aws_iam_role.control_plane.id

  policy = data.aws_iam_policy_document.control_plane_runtime.json
}

# Instance profile wrapping the control plane role
resource "aws_iam_instance_profile" "control_plane" {
  name = "${local.name_prefix}-control-plane"
  role = aws_iam_role.control_plane.name

  tags = local.tags
}
