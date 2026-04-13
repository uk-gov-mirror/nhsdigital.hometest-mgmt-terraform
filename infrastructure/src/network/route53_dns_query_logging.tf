################################################################################
# Route 53 DNS Query Logging to S3 (Near Real-Time)
################################################################################

#------------------------------------------------------------------------------
# S3 Bucket for DNS Query Logs
#------------------------------------------------------------------------------

resource "aws_s3_bucket" "dns_query_logs" {
  count = var.enable_dns_query_logging ? 1 : 0

  bucket = "${local.resource_prefix}-dns-query-logs"

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-dns-query-logs"
  })
}

resource "aws_s3_bucket_versioning" "dns_query_logs" {
  count = var.enable_dns_query_logging ? 1 : 0

  bucket = aws_s3_bucket.dns_query_logs[0].id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "dns_query_logs" {
  count = var.enable_dns_query_logging ? 1 : 0

  bucket = aws_s3_bucket.dns_query_logs[0].id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = var.logs_kms_key_arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled       = true
    blocked_encryption_types = ["NONE"]
  }
}

resource "aws_s3_bucket_public_access_block" "dns_query_logs" {
  count = var.enable_dns_query_logging ? 1 : 0

  bucket = aws_s3_bucket.dns_query_logs[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "dns_query_logs" {
  count = var.enable_dns_query_logging ? 1 : 0

  bucket = aws_s3_bucket.dns_query_logs[0].id

  rule {
    id     = "expire-old-logs"
    status = "Enabled"

    filter {}

    expiration {
      days = var.dns_query_logs_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 60
      storage_class = "GLACIER"
    }
  }
}

resource "aws_s3_bucket_policy" "dns_query_logs" {
  count = var.enable_dns_query_logging ? 1 : 0

  bucket = aws_s3_bucket.dns_query_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowFirehoseDelivery"
        Effect = "Allow"
        Principal = {
          Service = "firehose.amazonaws.com"
        }
        Action = [
          "s3:AbortMultipartUpload",
          "s3:GetBucketLocation",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:ListBucketMultipartUploads",
          "s3:PutObject"
        ]
        Resource = [
          aws_s3_bucket.dns_query_logs[0].arn,
          "${aws_s3_bucket.dns_query_logs[0].arn}/*"
        ]
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Sid       = "EnforceTLS"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.dns_query_logs[0].arn,
          "${aws_s3_bucket.dns_query_logs[0].arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

#------------------------------------------------------------------------------
# CloudWatch Log Group for Route 53 DNS Queries
# Note: Route 53 Query Logging requires log group in us-east-1
#------------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "dns_query_logs" {
  count = var.enable_dns_query_logging ? 1 : 0

  provider = aws.us_east_1

  name              = "/aws/route53/${aws_route53_zone.main.name}"
  retention_in_days = var.dns_query_logs_cloudwatch_retention_days
  # Note: KMS encryption for CloudWatch in us-east-1 requires a us-east-1 KMS key
  # For simplicity, we use AWS managed encryption here. Create a us-east-1 KMS key if needed.

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-dns-query-logs"
  })
}

#------------------------------------------------------------------------------
# CloudWatch Log Resource Policy (Required for Route 53)
#------------------------------------------------------------------------------

resource "aws_cloudwatch_log_resource_policy" "dns_query_logs" {
  count = var.enable_dns_query_logging ? 1 : 0

  provider = aws.us_east_1

  policy_name = "${local.resource_prefix}-dns-query-log-policy"

  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Route53LogsToCloudWatchLogs"
        Effect = "Allow"
        Principal = {
          Service = "route53.amazonaws.com"
        }
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:us-east-1:${data.aws_caller_identity.current.account_id}:log-group:/aws/route53/*:*"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
          ArnLike = {
            "aws:SourceArn" = aws_route53_zone.main.arn
          }
        }
      }
    ]
  })
}

#------------------------------------------------------------------------------
# Route 53 Query Logging Configuration
#------------------------------------------------------------------------------

resource "aws_route53_query_log" "main" {
  count = var.enable_dns_query_logging ? 1 : 0

  cloudwatch_log_group_arn = aws_cloudwatch_log_group.dns_query_logs[0].arn
  zone_id                  = aws_route53_zone.main.zone_id

  depends_on = [aws_cloudwatch_log_resource_policy.dns_query_logs]
}

#------------------------------------------------------------------------------
# Kinesis Data Firehose for Near Real-Time S3 Delivery
#------------------------------------------------------------------------------

resource "aws_iam_role" "dns_query_firehose" {
  count = var.enable_dns_query_logging ? 1 : 0

  name = "${local.resource_prefix}-dns-query-firehose-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "firehose.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-dns-query-firehose-role"
  })
}

resource "aws_iam_role_policy" "dns_query_firehose" {
  count = var.enable_dns_query_logging ? 1 : 0

  name = "${local.resource_prefix}-dns-query-firehose-policy"
  role = aws_iam_role.dns_query_firehose[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3Access"
        Effect = "Allow"
        Action = [
          "s3:AbortMultipartUpload",
          "s3:GetBucketLocation",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:ListBucketMultipartUploads",
          "s3:PutObject"
        ]
        Resource = [
          aws_s3_bucket.dns_query_logs[0].arn,
          "${aws_s3_bucket.dns_query_logs[0].arn}/*"
        ]
      },
      {
        Sid    = "KMSAccess"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = var.logs_kms_key_arn
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/kinesisfirehose/${local.resource_prefix}-dns-query-logs:*"
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "dns_query_firehose" {
  count = var.enable_dns_query_logging ? 1 : 0

  name              = "/aws/kinesisfirehose/${local.resource_prefix}-dns-query-logs"
  retention_in_days = 7
  kms_key_id        = var.logs_kms_key_arn

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-dns-query-firehose-logs"
  })
}

resource "aws_cloudwatch_log_stream" "dns_query_firehose" {
  count = var.enable_dns_query_logging ? 1 : 0

  name           = "S3Delivery"
  log_group_name = aws_cloudwatch_log_group.dns_query_firehose[0].name
}

resource "aws_kinesis_firehose_delivery_stream" "dns_query_logs" {
  count = var.enable_dns_query_logging ? 1 : 0

  name        = "${local.resource_prefix}-dns-query-logs"
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn            = aws_iam_role.dns_query_firehose[0].arn
    bucket_arn          = aws_s3_bucket.dns_query_logs[0].arn
    prefix              = "dns-query-logs/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/"
    error_output_prefix = "dns-query-logs-errors/!{firehose:error-output-type}/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/"

    # Near real-time buffering configuration
    buffering_size     = var.dns_query_logs_buffer_size
    buffering_interval = var.dns_query_logs_buffer_interval

    compression_format = "GZIP"

    cloudwatch_logging_options {
      enabled         = true
      log_group_name  = aws_cloudwatch_log_group.dns_query_firehose[0].name
      log_stream_name = aws_cloudwatch_log_stream.dns_query_firehose[0].name
    }

    # Server-side encryption
    s3_backup_mode = "Disabled"
  }

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-dns-query-logs-firehose"
  })
}

#------------------------------------------------------------------------------
# CloudWatch Logs Subscription Filter to Firehose
#------------------------------------------------------------------------------

resource "aws_iam_role" "dns_logs_subscription" {
  count = var.enable_dns_query_logging ? 1 : 0

  provider = aws.us_east_1

  name = "${local.resource_prefix}-dns-logs-subscription-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "logs.us-east-1.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-dns-logs-subscription-role"
  })
}

resource "aws_iam_role_policy" "dns_logs_subscription" {
  count = var.enable_dns_query_logging ? 1 : 0

  provider = aws.us_east_1

  name = "${local.resource_prefix}-dns-logs-subscription-policy"
  role = aws_iam_role.dns_logs_subscription[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "FirehoseAccess"
        Effect = "Allow"
        Action = [
          "firehose:PutRecord",
          "firehose:PutRecordBatch"
        ]
        Resource = aws_kinesis_firehose_delivery_stream.dns_query_logs[0].arn
      }
    ]
  })
}

resource "aws_cloudwatch_log_subscription_filter" "dns_query_logs" {
  count = var.enable_dns_query_logging ? 1 : 0

  provider = aws.us_east_1

  name            = "${local.resource_prefix}-dns-query-logs-to-s3"
  log_group_name  = aws_cloudwatch_log_group.dns_query_logs[0].name
  filter_pattern  = ""
  destination_arn = aws_kinesis_firehose_delivery_stream.dns_query_logs[0].arn
  role_arn        = aws_iam_role.dns_logs_subscription[0].arn

  depends_on = [
    aws_iam_role_policy.dns_logs_subscription
  ]
}

#------------------------------------------------------------------------------
# Optional: Private Zone DNS Query Logging
#------------------------------------------------------------------------------

resource "aws_route53_resolver_query_log_config" "private" {
  count = var.enable_dns_query_logging && var.create_private_hosted_zone ? 1 : 0

  name            = "${local.resource_prefix}-private-dns-query-logs"
  destination_arn = aws_s3_bucket.dns_query_logs[0].arn

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-private-dns-query-logs"
  })
}

resource "aws_route53_resolver_query_log_config_association" "private" {
  count = var.enable_dns_query_logging && var.create_private_hosted_zone ? 1 : 0

  resolver_query_log_config_id = aws_route53_resolver_query_log_config.private[0].id
  resource_id                  = aws_vpc.main.id
}
