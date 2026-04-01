################################################################################
# KMS Key for State Encryption (Security Best Practice)
################################################################################

locals {
  tfstate_kms_key_name = "${local.resource_prefix}-kms-tfstate-key"
}

resource "aws_kms_key" "tfstate" {
  description             = "KMS key for Terraform state encryption"
  deletion_window_in_days = var.kms_key_deletion_window_days
  enable_key_rotation     = true # Security best practice

  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "tfstate-key-policy"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.aws_account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow GitHub Actions Role"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.gha_oidc_role.arn
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = local.tfstate_kms_key_name
  })
}

resource "aws_kms_alias" "tfstate" {
  name          = "alias/${local.tfstate_kms_key_name}"
  target_key_id = aws_kms_key.tfstate.key_id
}
