################################################################################
# S3 Bucket for Terraform State
################################################################################

locals {
  tfstate_s3_bucket_name = "${local.resource_prefix}-s3-tfstate"
}

resource "aws_s3_bucket" "tfstate" {
  bucket = local.tfstate_s3_bucket_name

  lifecycle {
    prevent_destroy = true
  }

  tags = merge(local.common_tags, {
    Name = local.tfstate_s3_bucket_name
  })
}

# Enable versioning for state history and recovery
resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Server-side encryption with KMS
resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.tfstate.arn
    }
    bucket_key_enabled = true # Reduces KMS costs
  }
}

# Block all public access (Security Best Practice)
resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Enforce SSL/TLS connections only
resource "aws_s3_bucket_policy" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnforceSSLOnly"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.tfstate.arn,
          "${aws_s3_bucket.tfstate.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      },
      {
        Sid       = "EnforceTLSVersion"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.tfstate.arn,
          "${aws_s3_bucket.tfstate.arn}/*"
        ]
        Condition = {
          NumericLessThan = {
            "s3:TlsVersion" = "1.2"
          }
        }
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.tfstate]
}

# Lifecycle rules for cost optimization
resource "aws_s3_bucket_lifecycle_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    id     = "noncurrent-version-expiration"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = var.state_bucket_retention_days
    }

    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "STANDARD_IA"
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.tfstate]
}
