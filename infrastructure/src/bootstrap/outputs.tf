################################################################################
# Outputs
################################################################################

# S3 State Bucket Outputs
output "state_bucket_name" {
  description = "Name of the S3 bucket for Terraform state"
  value       = aws_s3_bucket.tfstate.id
}

output "state_bucket_arn" {
  description = "ARN of the S3 bucket for Terraform state"
  value       = aws_s3_bucket.tfstate.arn
}

# KMS Key Outputs
output "kms_key_arn" {
  description = "ARN of the KMS key for state encryption"
  value       = aws_kms_key.tfstate.arn
}

output "kms_key_alias" {
  description = "Alias of the KMS key for state encryption"
  value       = aws_kms_alias.tfstate.name
}

# OIDC Provider Outputs
output "github_oidc_provider_arn" {
  description = "ARN of the GitHub OIDC provider"
  value       = aws_iam_openid_connect_provider.github.arn
}

# IAM Role Outputs
output "gha_oidc_role_arn" {
  description = "ARN of the GitHub Actions OIDC role (store as AWS_ROLE_ARN in GitHub secrets)"
  value       = aws_iam_role.gha_oidc_role.arn
}

output "gha_oidc_role_name" {
  description = "Name of the GitHub Actions OIDC role"
  value       = aws_iam_role.gha_oidc_role.name
}

# Logging Bucket Outputs
output "logging_bucket_name" {
  description = "Name of the S3 bucket for access logs"
  value       = var.enable_state_bucket_logging ? aws_s3_bucket.tfstate_logs[0].id : null
}

# Backend Configuration Output
output "backend_config_hcl" {
  description = "Terraform backend configuration in HCL format"
  value       = <<-EOT
    bucket         = "${aws_s3_bucket.tfstate.id}"
    region         = "${var.aws_region}"
    use_lockfile   = true
    encrypt        = true
    kms_key_id     = "${aws_kms_key.tfstate.arn}"
  EOT
}
