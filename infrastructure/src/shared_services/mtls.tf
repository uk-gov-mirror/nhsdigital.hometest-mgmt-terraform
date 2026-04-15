################################################################################
# Mutual TLS (mTLS) — CA certificate, truststore, and client credentials
#
# Creates:
#   1. Self-signed CA (private key + certificate) for signing client certs
#   2. Client certificate signed by the CA (for API consumers)
#   3. S3 bucket with the CA cert as a truststore for API Gateway mTLS
#   4. Secrets Manager entries for the CA key and client key+cert
#
# Usage:
#   Pass `mtls_truststore_uri` output to API Gateway's
#   mutual_tls_authentication.truststore_uri to enable mTLS.
################################################################################

locals {
  mtls_enabled = var.enable_mtls
}

################################################################################
# CA — Private key and self-signed root certificate
################################################################################

resource "tls_private_key" "mtls_ca" {
  count = local.mtls_enabled ? 1 : 0

  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "tls_self_signed_cert" "mtls_ca" {
  count = local.mtls_enabled ? 1 : 0

  private_key_pem = tls_private_key.mtls_ca[0].private_key_pem

  subject {
    common_name         = "${var.project_name} mTLS CA"
    organization        = var.project_name
    organizational_unit = "Platform"
  }

  validity_period_hours = var.mtls_ca_validity_hours
  is_ca_certificate     = true
  set_subject_key_id    = true

  allowed_uses = [
    "cert_signing",
    "crl_signing",
  ]
}

################################################################################
# Client — Private key and certificate signed by the CA
################################################################################

resource "tls_private_key" "mtls_client" {
  count = local.mtls_enabled ? 1 : 0

  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_cert_request" "mtls_client" {
  count = local.mtls_enabled ? 1 : 0

  private_key_pem = tls_private_key.mtls_client[0].private_key_pem

  subject {
    common_name         = "${var.project_name} API Client"
    organization        = var.project_name
    organizational_unit = "Applications"
  }
}

resource "tls_locally_signed_cert" "mtls_client" {
  count = local.mtls_enabled ? 1 : 0

  cert_request_pem   = tls_cert_request.mtls_client[0].cert_request_pem
  ca_private_key_pem = tls_private_key.mtls_ca[0].private_key_pem
  ca_cert_pem        = tls_self_signed_cert.mtls_ca[0].cert_pem

  validity_period_hours = var.mtls_client_validity_hours
  set_subject_key_id    = true

  allowed_uses = [
    "digital_signature",
    "key_encipherment",
    "client_auth",
  ]
}

################################################################################
# S3 Bucket — Truststore for API Gateway mTLS
################################################################################

#checkov:skip=CKV_AWS_18:Access logging unnecessary for a truststore bucket containing only a public CA cert
resource "aws_s3_bucket" "mtls_truststore" { # NOSONAR - HTTPS enforced via DenyNonSSL+EnforceTLSVersion bucket policy; access logging not needed for public CA cert
  count = local.mtls_enabled ? 1 : 0

  bucket = "${local.resource_prefix}-mtls-truststore"

  tags = merge(local.common_tags, {
    Name         = "${local.resource_prefix}-mtls-truststore"
    ResourceType = "s3-bucket"
    Purpose      = "mtls-truststore"
  })
}

resource "aws_s3_bucket_versioning" "mtls_truststore" {
  count  = local.mtls_enabled ? 1 : 0
  bucket = aws_s3_bucket.mtls_truststore[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "mtls_truststore" {
  count  = local.mtls_enabled ? 1 : 0
  bucket = aws_s3_bucket.mtls_truststore[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.main.arn
    }
    bucket_key_enabled       = true
    blocked_encryption_types = ["SSE-C"]
  }
}

resource "aws_s3_bucket_public_access_block" "mtls_truststore" {
  count  = local.mtls_enabled ? 1 : 0
  bucket = aws_s3_bucket.mtls_truststore[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "mtls_truststore" {
  count  = local.mtls_enabled ? 1 : 0
  bucket = aws_s3_bucket.mtls_truststore[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyNonSSL"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.mtls_truststore[0].arn,
          "${aws_s3_bucket.mtls_truststore[0].arn}/*"
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
          aws_s3_bucket.mtls_truststore[0].arn,
          "${aws_s3_bucket.mtls_truststore[0].arn}/*"
        ]
        Condition = {
          NumericLessThan = {
            "s3:TlsVersion" = "1.2"
          }
        }
      },
      {
        Sid    = "AllowAPIGatewayRead"
        Effect = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion"
        ]
        Resource = "${aws_s3_bucket.mtls_truststore[0].arn}/${aws_s3_object.mtls_truststore[0].key}"
      },
      {
        Sid       = "DenyUnencryptedPut"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.mtls_truststore[0].arn}/*"
        Condition = {
          StringNotEquals = {
            "s3:x-amz-server-side-encryption" = "aws:kms"
          }
        }
      }
    ]
  })
}

################################################################################
# Upload CA certificate as the truststore
################################################################################

resource "aws_s3_object" "mtls_truststore" {
  count = local.mtls_enabled ? 1 : 0

  bucket                 = aws_s3_bucket.mtls_truststore[0].id
  key                    = "truststore.pem"
  content                = tls_self_signed_cert.mtls_ca[0].cert_pem
  content_type           = "application/x-pem-file"
  server_side_encryption = "aws:kms"
  kms_key_id             = aws_kms_key.main.arn

  # Ensure versioning is enabled before uploading so that version_id is a real
  # version string rather than the literal "null" that S3 returns for
  # unversioned objects.
  depends_on = [aws_s3_bucket_versioning.mtls_truststore]

  tags = merge(local.common_tags, {
    ResourceType = "truststore"
  })
}

################################################################################
# Secrets Manager — Store private keys and client certificate
################################################################################

resource "aws_secretsmanager_secret" "mtls_ca_private_key" {
  count = local.mtls_enabled ? 1 : 0

  name        = "${local.resource_prefix}/mtls/ca-private-key"
  description = "mTLS CA private key — used to sign new client certificates"
  kms_key_id  = aws_kms_key.pii_data.arn

  tags = merge(local.common_tags, {
    ResourceType = "secret"
    Purpose      = "mtls-ca-key"
  })
}

resource "aws_secretsmanager_secret_version" "mtls_ca_private_key" {
  count = local.mtls_enabled ? 1 : 0

  secret_id     = aws_secretsmanager_secret.mtls_ca_private_key[0].id
  secret_string = tls_private_key.mtls_ca[0].private_key_pem
}

resource "aws_secretsmanager_secret" "mtls_client_credentials" {
  count = local.mtls_enabled ? 1 : 0

  name        = "${local.resource_prefix}/mtls/client-credentials"
  description = "mTLS client private key and certificate — distribute to API consumers"
  kms_key_id  = aws_kms_key.pii_data.arn

  tags = merge(local.common_tags, {
    ResourceType = "secret"
    Purpose      = "mtls-client-cert"
  })
}

resource "aws_secretsmanager_secret_version" "mtls_client_credentials" {
  count = local.mtls_enabled ? 1 : 0

  secret_id = aws_secretsmanager_secret.mtls_client_credentials[0].id
  secret_string = jsonencode({
    client_certificate = tls_locally_signed_cert.mtls_client[0].cert_pem
    client_private_key = tls_private_key.mtls_client[0].private_key_pem
    ca_certificate     = tls_self_signed_cert.mtls_ca[0].cert_pem
  })
}
