# Session-archive bucket: `devbox release --keep` uploads one
# sessions/<session-id>.tar.gz per archived session; `claim --resume` reads it
# back. Devbox hosts never touch S3 directly — the server presigns PUT/GET URLs
# against the task role (see data.tf), so the only S3 grants in the platform
# live on the control plane.
#
# SSE-S3 (AES256), not a CMK: presigned URLs then need no kms grants for the
# uploader/downloader. No versioning — sessions are immutable one-shot objects
# with a TTL; the lifecycle rule below expires them on the same clock as the
# server-side SessionDoc records (SESSION_TTL_DAYS).

resource "aws_s3_bucket" "sessions" {
  bucket = "${local.name_prefix}-sessions-${local.aws_account_id}"

  tags = local.tags
}

resource "aws_s3_bucket_public_access_block" "sessions" {
  bucket = aws_s3_bucket.sessions.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "sessions" {
  bucket = aws_s3_bucket.sessions.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "sessions" {
  bucket = aws_s3_bucket.sessions.id

  rule {
    id     = "expire-sessions"
    status = "Enabled"

    filter {
      prefix = "sessions/"
    }

    expiration {
      days = var.session_ttl_days
    }
  }

  rule {
    id     = "abort-incomplete-uploads"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}
