################################################################################
# S3 Bucket for Terraform State
################################################################################

locals {
  tfstate_logs_s3_bucket_name = "${local.resource_prefix}-s3-tfstate-logs"
}

# Access logging for audit trail (Conditional)
resource "aws_s3_bucket" "tfstate_logs" {
  count  = var.enable_state_bucket_logging ? 1 : 0
  bucket = local.tfstate_logs_s3_bucket_name

  tags = merge(local.common_tags, {
    Name = local.tfstate_logs_s3_bucket_name
  })
}

resource "aws_s3_bucket_versioning" "tfstate_logs" {
  count  = var.enable_state_bucket_logging ? 1 : 0
  bucket = aws_s3_bucket.tfstate_logs[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate_logs" {
  count  = var.enable_state_bucket_logging ? 1 : 0
  bucket = aws_s3_bucket.tfstate_logs[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.logs.arn
    }
    bucket_key_enabled       = true
    blocked_encryption_types = ["NONE"]
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate_logs" {
  count  = var.enable_state_bucket_logging ? 1 : 0
  bucket = aws_s3_bucket.tfstate_logs[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "tfstate_logs" {
  count  = var.enable_state_bucket_logging ? 1 : 0
  bucket = aws_s3_bucket.tfstate_logs[0].id

  rule {
    id     = "log-expiration"
    status = "Enabled"

    expiration {
      days = 365
    }

    transition {
      days          = 90
      storage_class = "STANDARD_IA"
    }
  }
}

resource "aws_s3_bucket_logging" "tfstate" {
  count  = var.enable_state_bucket_logging ? 1 : 0
  bucket = aws_s3_bucket.tfstate.id

  target_bucket = aws_s3_bucket.tfstate_logs[0].id
  target_prefix = "access-logs/"
}
