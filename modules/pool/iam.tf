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
