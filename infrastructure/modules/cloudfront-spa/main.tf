################################################################################
# CloudFront SPA Module
# CloudFront distribution for SPA with S3 origin and security best practices
# Supports multiple API origins with path-based routing
################################################################################

locals {
  distribution_name = "${var.project_name}-${var.aws_account_shortname}-${var.environment}-spa"
  s3_origin_id      = "S3-${var.project_name}-${var.aws_account_shortname}-${var.environment}-spa"

  # Build map of API origins (supports both new api_origins and legacy api_gateway_domain_name)
  api_origins_map = length(var.api_origins) > 0 ? var.api_origins : (
    var.api_gateway_domain_name != null ? {
      "api" = {
        domain_name = var.api_gateway_domain_name
        origin_path = var.api_gateway_origin_path
      }
    } : {}
  )

  common_tags = merge(
    var.tags,
    {
      Name         = local.distribution_name
      Service      = "cloudfront"
      ManagedBy    = "terraform"
      Module       = "cloudfront-spa"
      ResourceType = "distribution"
    }
  )
}

################################################################################
# S3 Bucket for SPA Static Assets
################################################################################

resource "aws_s3_bucket" "spa" {
  bucket        = "${var.project_name}-${var.aws_account_shortname}-${var.environment}-spa"
  force_destroy = true

  tags = merge(local.common_tags, {
    ResourceType = "s3-bucket"
    Purpose      = "spa-static-assets"
  })
}

# Block all public access - all four settings must remain true at all times.
# The SPA is served exclusively via CloudFront OAC; direct S3 access must be blocked.
# trivy:ignore:AVD-AWS-0086 trivy:ignore:AVD-AWS-0087 trivy:ignore:AVD-AWS-0088 trivy:ignore:AVD-AWS-0132
resource "aws_s3_bucket_public_access_block" "spa" {
  bucket = aws_s3_bucket.spa.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  # lifecycle {
  #   # Prevent accidental removal or loosening of the public access block.
  #   # If you intentionally need to change these, remove this block temporarily,
  #   # apply, reconfigure, then re-add it.
  #   prevent_destroy = true
  # }
}

# Enable versioning for rollback capability
resource "aws_s3_bucket_versioning" "spa" {
  bucket = aws_s3_bucket.spa.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "spa" {
  bucket = aws_s3_bucket.spa.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.s3_kms_key_arn != null ? "aws:kms" : "AES256"
      kms_master_key_id = var.s3_kms_key_arn
    }
    bucket_key_enabled       = var.s3_kms_key_arn != null
    blocked_encryption_types = ["SSE-C"]
  }
}

# Lifecycle rules for cost optimization
resource "aws_s3_bucket_lifecycle_configuration" "spa" {
  bucket = aws_s3_bucket.spa.id

  rule {
    id     = "cleanup-old-versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = var.s3_noncurrent_version_expiration_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# S3 bucket policy for CloudFront OAC + SSL enforcement (S3.5)
resource "aws_s3_bucket_policy" "spa" {
  bucket = aws_s3_bucket.spa.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontOAC"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.spa.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.spa.arn
          }
        }
      },
      {
        Sid       = "DenyNonSSL"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.spa.arn,
          "${aws_s3_bucket.spa.arn}/*"
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
          aws_s3_bucket.spa.arn,
          "${aws_s3_bucket.spa.arn}/*"
        ]
        Condition = {
          NumericLessThan = {
            "s3:TlsVersion" = "1.2"
          }
        }
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.spa]
}

################################################################################
# S3 Server Access Logging (S3.9)
# NOSONAR: This is the log-destination bucket — it cannot log to itself
# (infinite loop). HTTPS is enforced via DenyNonSSL + EnforceTLSVersion
# statements in aws_s3_bucket_policy.spa_logs below. Log delivery uses the
# modern bucket-policy grant (logging.s3.amazonaws.com principal) instead of
# the deprecated ACL "log-delivery-write".
################################################################################

resource "aws_s3_bucket" "spa_logs" { # NOSONAR — log target bucket; policy enforces HTTPS; no self-logging
  bucket        = "${var.project_name}-${var.environment}-spa-logs"
  force_destroy = true

  tags = merge(local.common_tags, {
    ResourceType = "s3-bucket"
    Purpose      = "spa-access-logs"
  })
}

resource "aws_s3_bucket_public_access_block" "spa_logs" {
  bucket = aws_s3_bucket.spa_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "spa_logs" {
  bucket = aws_s3_bucket.spa_logs.id

  rule {
    apply_server_side_encryption_by_default {
      # S3 server access log delivery only supports SSE-S3 (AES256), not SSE-KMS
      sse_algorithm = "AES256"
    }
    blocked_encryption_types = ["SSE-C"]
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "spa_logs" {
  bucket = aws_s3_bucket.spa_logs.id

  rule {
    id     = "expire-access-logs"
    status = "Enabled"

    expiration {
      days = var.s3_access_log_retention_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# Grant logging.s3.amazonaws.com permission to deliver logs + enforce SSL
resource "aws_s3_bucket_policy" "spa_logs" {
  bucket = aws_s3_bucket.spa_logs.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowS3LogDelivery"
        Effect = "Allow"
        Principal = {
          Service = "logging.s3.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.spa_logs.arn}/s3-access-logs/*"
        Condition = {
          ArnLike = {
            "aws:SourceArn" = aws_s3_bucket.spa.arn
          }
          StringEquals = {
            "aws:SourceAccount" = var.aws_account_id
          }
        }
      },
      {
        Sid       = "DenyNonSSL"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.spa_logs.arn,
          "${aws_s3_bucket.spa_logs.arn}/*"
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
          aws_s3_bucket.spa_logs.arn,
          "${aws_s3_bucket.spa_logs.arn}/*"
        ]
        Condition = {
          NumericLessThan = {
            "s3:TlsVersion" = "1.2"
          }
        }
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.spa_logs]
}

resource "aws_s3_bucket_logging" "spa" {
  bucket        = aws_s3_bucket.spa.id
  target_bucket = aws_s3_bucket.spa_logs.id
  target_prefix = "s3-access-logs/"

  depends_on = [aws_s3_bucket_policy.spa_logs]
}

################################################################################
# CloudFront Origin Access Control (OAC)
################################################################################

resource "aws_cloudfront_origin_access_control" "spa" {
  name                              = local.distribution_name
  description                       = "OAC for ${local.distribution_name}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

################################################################################
# CloudFront Response Headers Policy
################################################################################

resource "aws_cloudfront_response_headers_policy" "security_headers" {
  name    = "${local.distribution_name}-security-headers"
  comment = "Security headers for ${local.distribution_name}"

  security_headers_config {
    content_type_options {
      override = true
    }

    frame_options {
      frame_option = "DENY"
      override     = true
    }

    referrer_policy {
      referrer_policy = "strict-origin-when-cross-origin"
      override        = true
    }

    xss_protection {
      mode_block = true
      protection = true
      override   = true
    }

    strict_transport_security {
      access_control_max_age_sec = 31536000
      include_subdomains         = true
      preload                    = true
      override                   = true
    }

    content_security_policy {
      content_security_policy = var.content_security_policy
      override                = true
    }
  }

  custom_headers_config {
    items {
      header   = "Permissions-Policy"
      value    = var.permissions_policy
      override = true
    }
  }
}

################################################################################
# CloudFront Cache Policy for SPA
################################################################################

resource "aws_cloudfront_cache_policy" "spa" {
  name        = "${local.distribution_name}-cache-policy"
  comment     = "Cache policy for SPA static assets"
  default_ttl = 86400    # 1 day
  max_ttl     = 31536000 # 1 year
  min_ttl     = 0

  parameters_in_cache_key_and_forwarded_to_origin {
    cookies_config {
      cookie_behavior = "none"
    }
    headers_config {
      header_behavior = "none"
    }
    query_strings_config {
      query_string_behavior = "none"
    }
    enable_accept_encoding_brotli = true
    enable_accept_encoding_gzip   = true
  }
}

################################################################################
# CloudFront Distribution
################################################################################

resource "aws_cloudfront_distribution" "spa" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "CloudFront distribution for ${local.distribution_name}"
  default_root_object = "index.html"
  price_class         = var.price_class
  http_version        = "http2and3"
  aliases             = var.custom_domain_names

  # S3 Origin for static assets
  origin {
    domain_name              = aws_s3_bucket.spa.bucket_regional_domain_name
    origin_id                = local.s3_origin_id
    origin_access_control_id = aws_cloudfront_origin_access_control.spa.id
  }

  # Dynamic API Gateway Origins (supports multiple APIs)
  dynamic "origin" {
    for_each = local.api_origins_map
    content {
      domain_name = origin.value.domain_name
      origin_id   = "API-${origin.key}"
      origin_path = origin.value.origin_path

      custom_origin_config {
        http_port              = 80
        https_port             = 443
        origin_protocol_policy = "https-only"
        origin_ssl_protocols   = ["TLSv1.2"]
      }
    }
  }

  # Default behavior for SPA
  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id

    cache_policy_id            = aws_cloudfront_cache_policy.spa.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.security_headers.id

    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    # Function associations for SPA routing
    dynamic "function_association" {
      for_each = var.enable_spa_routing ? [1] : []
      content {
        event_type   = "viewer-request"
        function_arn = aws_cloudfront_function.spa_routing[0].arn
      }
    }
  }

  # Dynamic API path behaviors (supports multiple APIs with different paths)
  # Pattern: /{prefix}/* for paths like /order-router/something
  dynamic "ordered_cache_behavior" {
    for_each = local.api_origins_map
    content {
      path_pattern     = "/${ordered_cache_behavior.key}/*"
      allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
      cached_methods   = ["GET", "HEAD"]
      target_origin_id = "API-${ordered_cache_behavior.key}"

      # No caching for API calls
      cache_policy_id          = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" # CachingDisabled
      origin_request_policy_id = "b689b0a8-53d0-40ab-baf2-68738e2966ac" # AllViewerExceptHostHeader

      viewer_protocol_policy = "redirect-to-https"
      compress               = true
    }
  }

  # API root path behaviors (exact match for /{prefix} without trailing path)
  # Pattern: /{prefix} for paths like /order-router (no trailing slash or content)
  dynamic "ordered_cache_behavior" {
    for_each = local.api_origins_map
    content {
      path_pattern     = "/${ordered_cache_behavior.key}"
      allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
      cached_methods   = ["GET", "HEAD"]
      target_origin_id = "API-${ordered_cache_behavior.key}"

      # No caching for API calls
      cache_policy_id          = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" # CachingDisabled
      origin_request_policy_id = "b689b0a8-53d0-40ab-baf2-68738e2966ac" # AllViewerExceptHostHeader

      viewer_protocol_policy = "redirect-to-https"
      compress               = true
    }
  }

  # SPA routing for client-side routes
  custom_error_response {
    error_code            = 403
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 10
  }

  custom_error_response {
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 10
  }

  # Geo restrictions
  restrictions {
    geo_restriction {
      restriction_type = var.geo_restriction_type
      locations        = var.geo_restriction_locations
    }
  }

  # SSL/TLS Configuration
  viewer_certificate {
    cloudfront_default_certificate = var.acm_certificate_arn == null
    acm_certificate_arn            = var.acm_certificate_arn
    ssl_support_method             = var.acm_certificate_arn != null ? "sni-only" : null
    minimum_protocol_version       = var.acm_certificate_arn != null ? "TLSv1.2_2021" : null
  }

  # WAF Association
  web_acl_id = var.waf_web_acl_arn

  # Logging
  dynamic "logging_config" {
    for_each = var.enable_access_logging ? [1] : []
    content {
      include_cookies = false
      bucket          = var.logging_bucket_domain_name
      prefix          = "cloudfront/${local.distribution_name}/"
    }
  }

  tags = local.common_tags
}

################################################################################
# CloudFront Function for SPA Routing
################################################################################

locals {
  # Build regex pattern from API prefixes for the SPA routing function
  # Example: "api1|api2|hello-world|test-order"
  api_prefixes_pattern = join("|", [for k, v in local.api_origins_map : k])
}

resource "aws_cloudfront_function" "spa_routing" {
  count = var.enable_spa_routing ? 1 : 0

  name    = "${replace(local.distribution_name, "-", "_")}_spa_routing"
  runtime = "cloudfront-js-2.0"
  comment = "SPA routing function for ${local.distribution_name}"
  publish = true

  # Template the function with actual API prefixes
  code = replace(
    file("${path.module}/functions/spa_routing.js"),
    "$${API_PREFIXES_PATTERN}",
    local.api_prefixes_pattern != "" ? local.api_prefixes_pattern : "api"
  )
}

################################################################################
# Route53 Record (optional)
################################################################################

resource "aws_route53_record" "spa" {
  count = var.route53_zone_id != null && length(var.custom_domain_names) > 0 ? length(var.custom_domain_names) : 0

  zone_id = var.route53_zone_id
  name    = var.custom_domain_names[count.index]
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.spa.domain_name
    zone_id                = aws_cloudfront_distribution.spa.hosted_zone_id
    evaluate_target_health = false
  }
}
