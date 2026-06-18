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

# Custom inline policy: SSM Parameter Store publish for native AMI distribution
resource "aws_iam_role_policy" "ssm_publish" {
  name = "${local.name_prefix}-ssm-publish"
  role = aws_iam_role.build_instance.id

  policy = data.aws_iam_policy_document.ssm_publish.json
}

# Instance profile wrapping the build instance role
resource "aws_iam_instance_profile" "build_instance" {
  name = "${local.name_prefix}-instance-profile"
  role = aws_iam_role.build_instance.name

  tags = local.tags
}

# Lifecycle Policy Execution Role
#
# Provides permissions for the Image Builder lifecycle policy to deregister
# old AMIs and delete associated EBS snapshots.

resource "aws_iam_role" "lifecycle" {
  name               = "${local.name_prefix}-lifecycle"
  assume_role_policy = data.aws_iam_policy_document.lifecycle_assume_role.json

  tags = local.tags
}

resource "aws_iam_role_policy" "lifecycle" {
  name = "${local.name_prefix}-lifecycle"
  role = aws_iam_role.lifecycle.id

  policy = data.aws_iam_policy_document.lifecycle.json
}
