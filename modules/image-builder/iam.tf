# Build Instance IAM Role and Instance Profile
#
# Provides least-privilege permissions for EC2 Image Builder build instances.
# The role allows package installation, S3 artifact access, SSM communication,
# and AMI creation. It explicitly excludes IAM modification and production
# database access.

resource "aws_iam_role" "build_instance" {
  name               = "${local.name_prefix}-instance"
  assume_role_policy = data.aws_iam_policy_document.build_instance_assume_role.json

  tags = local.tags
}

# Managed policy: EC2 Image Builder base functionality
resource "aws_iam_role_policy_attachment" "image_builder" {
  role       = aws_iam_role.build_instance.name
  policy_arn = data.aws_iam_policy.image_builder.arn
}

# Managed policy: SSM-based instance management during builds
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.build_instance.name
  policy_arn = data.aws_iam_policy.ssm_core.arn
}

# Custom inline policy: S3 access for component artifacts
resource "aws_iam_role_policy" "s3_access" {
  count = var.s3_bucket_arn != "" ? 1 : 0

  name = "${local.name_prefix}-s3-access"
  role = aws_iam_role.build_instance.id

  policy = data.aws_iam_policy_document.s3_access[0].json
}

# Custom inline policy: Secrets Manager access for private Git repos
resource "aws_iam_role_policy" "secrets_access" {
  count = length(var.secrets_arns) > 0 ? 1 : 0

  name = "${local.name_prefix}-secrets-access"
  role = aws_iam_role.build_instance.id

  policy = data.aws_iam_policy_document.secrets_access[0].json
}

# Custom inline policy: test-stage workspace mount + warm-up. The exercise self-skips
# at runtime until a real workspace snapshot exists (see test-workspace-mount.sh), so
# the grants are harmless on a bootstrap apply.
resource "aws_iam_role_policy" "test_mount" {
  name = "${local.name_prefix}-test-mount"
  role = aws_iam_role.build_instance.id

  policy = data.aws_iam_policy_document.build_instance_test_mount.json
}

# Instance profile wrapping the build instance role
resource "aws_iam_instance_profile" "build_instance" {
  name = "${local.name_prefix}-instance-profile"
  role = aws_iam_role.build_instance.name

  tags = local.tags
}

# Pipeline Execution Role
#
# The pipeline runs its build, test, and distribution workflows under this role
# instead of the AWSServiceRoleForImageBuilder service-linked role. The managed
# EC2ImageBuilderExecutionPolicy provides the baseline workflow permissions; the
# inline policy adds ssm:PutParameter so distribution can publish the output AMI
# ID to /devbox/ami/latest, which the service-linked role cannot write because it
# is outside the /imagebuilder/ namespace.

resource "aws_iam_role" "execution" {
  name               = "${local.name_prefix}-execution"
  assume_role_policy = data.aws_iam_policy_document.imagebuilder_assume_role.json

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = data.aws_iam_policy.execution.arn
}

resource "aws_iam_role_policy" "execution" {
  name = "${local.name_prefix}-execution-features"
  role = aws_iam_role.execution.id

  policy = data.aws_iam_policy_document.execution.json
}

# Lifecycle Policy Execution Role
#
# Provides permissions for the Image Builder lifecycle policy to deregister
# old AMIs and delete associated EBS snapshots.

resource "aws_iam_role" "lifecycle" {
  name               = "${local.name_prefix}-lifecycle"
  assume_role_policy = data.aws_iam_policy_document.imagebuilder_assume_role.json

  tags = local.tags
}

resource "aws_iam_role_policy" "lifecycle" {
  name = "${local.name_prefix}-lifecycle"
  role = aws_iam_role.lifecycle.id

  policy = data.aws_iam_policy_document.lifecycle.json
}
