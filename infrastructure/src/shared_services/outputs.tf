################################################################################
# Shared Services Outputs
# These values are consumed by environment-specific deployments
################################################################################

#------------------------------------------------------------------------------
# KMS Key
#------------------------------------------------------------------------------

output "kms_key_arn" {
  description = "ARN of the shared KMS key"
  value       = aws_kms_key.main.arn
}

output "kms_key_id" {
  description = "ID of the shared KMS key"
  value       = aws_kms_key.main.key_id
}

output "kms_key_alias_arn" {
  description = "ARN of the KMS key alias"
  value       = aws_kms_alias.main.arn
}

output "pii_data_kms_key_arn" {
  description = "ARN of the PII data KMS key (for RDS, SQS, Secrets Manager)"
  value       = aws_kms_key.pii_data.arn
}

output "pii_data_kms_key_id" {
  description = "ID of the PII data KMS key"
  value       = aws_kms_key.pii_data.key_id
}

#------------------------------------------------------------------------------
# WAF Web ACLs
#------------------------------------------------------------------------------

output "waf_regional_arn" {
  description = "ARN of the regional WAF Web ACL (for API Gateway)"
  value       = aws_wafv2_web_acl.regional.arn
}

output "waf_regional_id" {
  description = "ID of the regional WAF Web ACL"
  value       = aws_wafv2_web_acl.regional.id
}

output "waf_cloudfront_arn" {
  description = "ARN of the CloudFront WAF Web ACL (for CloudFront distributions)"
  value       = aws_wafv2_web_acl.cloudfront.arn
}

output "waf_cloudfront_id" {
  description = "ID of the CloudFront WAF Web ACL"
  value       = aws_wafv2_web_acl.cloudfront.id
}

#------------------------------------------------------------------------------
# ACM Certificates
#------------------------------------------------------------------------------

output "acm_regional_certificate_arn" {
  description = "ARN of the regional ACM certificate (for API Gateway)"
  value       = var.create_acm_certificates ? aws_acm_certificate.regional[0].arn : null
}

output "acm_cloudfront_certificate_arn" {
  description = "ARN of the CloudFront ACM certificate (us-east-1)"
  value       = var.create_acm_certificates ? aws_acm_certificate.cloudfront[0].arn : null
}

output "acm_regional_certificate_validated" {
  description = "Whether the regional certificate has been validated"
  value       = var.create_acm_certificates ? aws_acm_certificate_validation.regional[0].id != null : false
}

output "acm_cloudfront_certificate_validated" {
  description = "Whether the CloudFront certificate has been validated"
  value       = var.create_acm_certificates ? aws_acm_certificate_validation.cloudfront[0].id != null : false
}

#------------------------------------------------------------------------------
# Deployment Artifacts
#------------------------------------------------------------------------------

# output "deployment_artifacts_bucket_id" {
#   description = "ID of the deployment artifacts S3 bucket"
#   value       = aws_s3_bucket.deployment_artifacts.id
# }

# output "deployment_artifacts_bucket_arn" {
#   description = "ARN of the deployment artifacts S3 bucket"
#   value       = aws_s3_bucket.deployment_artifacts.arn
# }

# output "deployment_artifacts_bucket_domain" {
#   description = "Domain name of the deployment artifacts bucket"
#   value       = aws_s3_bucket.deployment_artifacts.bucket_domain_name
# }


################################################################################
# SNS Topics
################################################################################

output "sns_alerts_topic_arn" {
  description = "ARN of the shared alerts SNS topic"
  value       = module.sns_alerts.topic_arn
}

output "developer_role_name" {
  description = "Name of the developer deployment role"
  value       = aws_iam_role.developer.name
}

#------------------------------------------------------------------------------
# Convenience Output - All shared resources for app deployment
#------------------------------------------------------------------------------

output "shared_config" {
  description = "All shared service configuration for app deployments"
  value = {
    kms_key_arn                    = aws_kms_key.main.arn
    waf_regional_arn               = aws_wafv2_web_acl.regional.arn
    waf_cloudfront_arn             = aws_wafv2_web_acl.cloudfront.arn
    acm_regional_certificate_arn   = var.create_acm_certificates ? aws_acm_certificate.regional[0].arn : null
    acm_cloudfront_certificate_arn = var.create_acm_certificates ? aws_acm_certificate.cloudfront[0].arn : null
    sns_alerts_topic_arn           = module.sns_alerts.topic_arn
    # deployment_bucket_id           = aws_s3_bucket.deployment_artifacts.id
    # deployment_bucket_arn          = aws_s3_bucket.deployment_artifacts.arn
    developer_role_arn = aws_iam_role.developer.arn
  }
}

#------------------------------------------------------------------------------
# Cognito User Pool Outputs
#------------------------------------------------------------------------------

output "cognito_user_pool_id" {
  description = "The ID of the Cognito User Pool"
  value       = var.enable_cognito ? aws_cognito_user_pool.main[0].id : null
}

output "cognito_user_pool_arn" {
  description = "The ARN of the Cognito User Pool"
  value       = var.enable_cognito ? aws_cognito_user_pool.main[0].arn : null
}

output "cognito_user_pool_endpoint" {
  description = "The endpoint of the Cognito User Pool"
  value       = var.enable_cognito ? aws_cognito_user_pool.main[0].endpoint : null
}

output "cognito_user_pool_domain" {
  description = "The domain of the Cognito User Pool"
  value       = var.enable_cognito ? aws_cognito_user_pool_domain.main[0].domain : null
}

output "cognito_user_pool_domain_cloudfront_distribution" {
  description = "The CloudFront distribution for the Cognito User Pool domain (for custom domains)"
  value       = var.enable_cognito && var.cognito_custom_domain != "" ? aws_cognito_user_pool_domain.main[0].cloudfront_distribution : null
}

output "cognito_user_pool_client_id" {
  description = "The ID of the Cognito User Pool Client"
  value       = var.enable_cognito ? aws_cognito_user_pool_client.main[0].id : null
}

output "cognito_user_pool_client_secret" {
  description = "The client secret of the Cognito User Pool Client"
  value       = var.enable_cognito && var.cognito_generate_client_secret ? aws_cognito_user_pool_client.main[0].client_secret : null
  sensitive   = true
}

output "cognito_resource_server_identifier" {
  description = "The identifier of the Cognito Resource Server"
  value       = var.enable_cognito && length(var.cognito_resource_server_scopes) > 0 ? aws_cognito_resource_server.main[0].identifier : null
}

output "cognito_resource_server_scopes" {
  description = "The scopes of the Cognito Resource Server"
  value       = var.enable_cognito && length(var.cognito_resource_server_scopes) > 0 ? aws_cognito_resource_server.main[0].scope_identifiers : null
}

output "cognito_identity_pool_id" {
  description = "The ID of the Cognito Identity Pool"
  value       = var.enable_cognito && var.enable_cognito_identity_pool ? aws_cognito_identity_pool.main[0].id : null
}

output "cognito_identity_pool_arn" {
  description = "The ARN of the Cognito Identity Pool"
  value       = var.enable_cognito && var.enable_cognito_identity_pool ? aws_cognito_identity_pool.main[0].arn : null
}

output "cognito_authenticated_role_arn" {
  description = "The ARN of the IAM role for authenticated Cognito users"
  value       = var.enable_cognito && var.enable_cognito_identity_pool ? aws_iam_role.cognito_authenticated[0].arn : null
}

output "cognito_unauthenticated_role_arn" {
  description = "The ARN of the IAM role for unauthenticated Cognito users"
  value       = var.enable_cognito && var.enable_cognito_identity_pool && var.cognito_allow_unauthenticated_identities ? aws_iam_role.cognito_unauthenticated[0].arn : null
}

output "cognito_hosted_ui_url" {
  description = "The URL for the Cognito Hosted UI"
  value       = var.enable_cognito ? "https://${aws_cognito_user_pool_domain.main[0].domain}.auth.${var.aws_region}.amazoncognito.com" : null
}

output "cognito_oauth_token_endpoint" {
  description = "The OAuth token endpoint URL"
  value       = var.enable_cognito ? "https://${aws_cognito_user_pool_domain.main[0].domain}.auth.${var.aws_region}.amazoncognito.com/oauth2/token" : null
}

output "cognito_oauth_authorize_endpoint" {
  description = "The OAuth authorize endpoint URL"
  value       = var.enable_cognito ? "https://${aws_cognito_user_pool_domain.main[0].domain}.auth.${var.aws_region}.amazoncognito.com/oauth2/authorize" : null
}

#------------------------------------------------------------------------------
# M2M App Client Outputs
#------------------------------------------------------------------------------

output "cognito_preventex_m2m_client_id" {
  description = "The client ID for Preventex M2M application"
  value       = var.enable_cognito ? aws_cognito_user_pool_client.preventex_m2m[0].id : null
}

output "cognito_preventex_m2m_client_secret" {
  description = "The client secret for Preventex M2M application"
  value       = var.enable_cognito ? aws_cognito_user_pool_client.preventex_m2m[0].client_secret : null
  sensitive   = true
}

output "cognito_results_resource_server_identifier" {
  description = "The resource server identifier for Results API"
  value       = var.enable_cognito ? aws_cognito_resource_server.results[0].identifier : null
}

output "cognito_orders_resource_server_identifier" {
  description = "The resource server identifier for Orders API"
  value       = var.enable_cognito ? aws_cognito_resource_server.orders[0].identifier : null
}

output "cognito_sh24_m2m_client_id" {
  description = "The client ID for SH:24 M2M application"
  value       = var.enable_cognito ? aws_cognito_user_pool_client.sh24_m2m[0].id : null
}

output "cognito_sh24_m2m_client_secret" {
  description = "The client secret for SH:24 M2M application"
  value       = var.enable_cognito ? aws_cognito_user_pool_client.sh24_m2m[0].client_secret : null
  sensitive   = true
}

output "cognito_internal_test_client_m2m_id" {
  description = "The client ID for the internal test M2M application"
  value       = var.enable_cognito ? aws_cognito_user_pool_client.internal_test_client_m2m[0].id : null
}

output "cognito_internal_test_client_m2m_secret" {
  description = "The client secret for the internal test M2M application"
  value       = var.enable_cognito ? aws_cognito_user_pool_client.internal_test_client_m2m[0].client_secret : null
  sensitive   = true
}

#------------------------------------------------------------------------------
# IAM Policies
#------------------------------------------------------------------------------

output "developer_deployment_policy_arn" {
  description = "ARN of the developer deployment IAM policy"
  value       = aws_iam_policy.developer_deployment.arn
}

output "tfstate_readonly_policy_arn" {
  description = "ARN of the Terraform state read-only IAM policy"
  value       = aws_iam_policy.tfstate_readonly.arn
}

#------------------------------------------------------------------------------
# Developer IAM
#------------------------------------------------------------------------------

output "developer_role_arn" {
  description = "ARN of the developer deployment role"
  value       = aws_iam_role.developer.arn
}

output "developer_deployment_policy_arns" {
  description = "Developer deployment policy ARN (consolidated policy for SSO permission set attachment)"
  value       = [aws_iam_policy.developer_deployment.arn]
}

output "developer_deployment_policy_name" {
  description = "Name of the developer deployment policy"
  value       = aws_iam_policy.developer_deployment.name
}

#------------------------------------------------------------------------------
# API Gateway Account (regional singleton)
#------------------------------------------------------------------------------

output "api_gateway_cloudwatch_role_arn" {
  description = "ARN of the IAM role used by API Gateway for CloudWatch logging (regional singleton)"
  value       = aws_iam_role.api_gateway_cloudwatch.arn
}
