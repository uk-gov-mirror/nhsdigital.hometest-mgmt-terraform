################################################################################
# HomeTest Service Application Outputs
################################################################################

#------------------------------------------------------------------------------
# Lambda Functions (Dynamic)
#------------------------------------------------------------------------------

output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = module.lambda_iam.role_arn
}

output "lambda_functions" {
  description = "Map of all Lambda function details"
  value = {
    for name, lambda in module.lambdas : name => {
      function_name = lambda.function_name
      function_arn  = lambda.function_arn
      invoke_arn    = lambda.function_invoke_arn
    }
  }
}

# Legacy outputs for backwards compatibility
output "api1_lambda_arn" {
  description = "ARN of the API 1 Lambda (legacy - use lambda_functions instead)"
  value       = try(module.lambdas["api1-handler"].function_arn, null)
}

output "api1_lambda_name" {
  description = "Name of the API 1 Lambda (legacy - use lambda_functions instead)"
  value       = try(module.lambdas["api1-handler"].function_name, null)
}

output "api2_lambda_arn" {
  description = "ARN of the API 2 Lambda (legacy - use lambda_functions instead)"
  value       = try(module.lambdas["api2-handler"].function_arn, null)
}

output "api2_lambda_name" {
  description = "Name of the API 2 Lambda (legacy - use lambda_functions instead)"
  value       = try(module.lambdas["api2-handler"].function_name, null)
}

#------------------------------------------------------------------------------
# API Gateway (Dynamic)
#------------------------------------------------------------------------------

output "api_gateways" {
  description = "Map of all API Gateway details"
  value = {
    for prefix in local.api_prefixes : prefix => {
      rest_api_id   = aws_api_gateway_rest_api.apis[prefix].id
      execution_arn = aws_api_gateway_rest_api.apis[prefix].execution_arn
      invoke_url    = aws_api_gateway_stage.apis[prefix].invoke_url
    }
  }
}

# Legacy outputs for backwards compatibility
output "api1_gateway_id" {
  description = "ID of API Gateway 1 (legacy - use api_gateways instead)"
  value       = try(aws_api_gateway_rest_api.apis["api1"].id, null)
}

output "api2_gateway_id" {
  description = "ID of API Gateway 2 (legacy - use api_gateways instead)"
  value       = try(aws_api_gateway_rest_api.apis["api2"].id, null)
}

#------------------------------------------------------------------------------
# CloudFront SPA
#------------------------------------------------------------------------------

output "spa_bucket_id" {
  description = "S3 bucket ID for SPA static assets"
  value       = module.cloudfront_spa.s3_bucket_id
}

output "spa_bucket_arn" {
  description = "S3 bucket ARN for SPA static assets"
  value       = module.cloudfront_spa.s3_bucket_arn
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID"
  value       = module.cloudfront_spa.distribution_id
}

output "cloudfront_distribution_arn" {
  description = "CloudFront distribution ARN"
  value       = module.cloudfront_spa.distribution_arn
}

output "cloudfront_domain_name" {
  description = "CloudFront distribution domain name"
  value       = module.cloudfront_spa.distribution_domain_name
}

output "spa_url" {
  description = "Full URL for SPA"
  value       = var.custom_domain_name != null ? "https://${var.custom_domain_name}" : module.cloudfront_spa.distribution_url
}

#------------------------------------------------------------------------------
# Login Endpoint (for frontend NEXT_PUBLIC_LOGIN_LAMBDA_ENDPOINT)
#------------------------------------------------------------------------------

output "login_endpoint" {
  description = "Login Lambda endpoint URL"
  value = (
    var.api_custom_domain_name != null
    ? "https://${var.api_custom_domain_name}/login"
    : try("${module.cloudfront_spa.distribution_url}/login", null)
  )
}

#------------------------------------------------------------------------------
# Environment URLs Summary (Dynamic)
# All services accessible via single domain with path-based routing
#------------------------------------------------------------------------------

output "environment_urls" {
  description = "All environment URLs"
  value = merge(
    {
      base_url = var.custom_domain_name != null ? "https://${var.custom_domain_name}" : module.cloudfront_spa.distribution_url
      ui       = var.custom_domain_name != null ? "https://${var.custom_domain_name}" : module.cloudfront_spa.distribution_url
      api      = var.api_custom_domain_name != null ? "https://${var.api_custom_domain_name}" : null
    },
    {
      for prefix in local.api_prefixes : prefix => (
        var.api_custom_domain_name != null
        ? "https://${var.api_custom_domain_name}/${prefix}"
        : (
          var.custom_domain_name != null
          ? "https://${var.custom_domain_name}/${prefix}"
          : "${module.cloudfront_spa.distribution_url}/${prefix}"
        )
      )
    }
  )
}

#------------------------------------------------------------------------------
# Deployment Info
#------------------------------------------------------------------------------

# output "deployment_bucket" {
#   description = "S3 bucket for deployment artifacts"
#   value       = var.deployment_bucket_id
# }

output "deployment_info" {
  description = "Information for CI/CD deployments"
  value = {
    environment   = var.environment
    spa_bucket    = module.cloudfront_spa.s3_bucket_id
    cloudfront_id = module.cloudfront_spa.distribution_id
    # deploy_bucket = var.deployment_bucket_id
    lambda_prefix = "lambdas/${var.environment}"
    lambdas       = [for name, _ in local.all_lambdas : name]
    api_prefixes  = [for prefix in local.api_prefixes : prefix]
  }
}

#------------------------------------------------------------------------------
# WireMock (when enabled)
#------------------------------------------------------------------------------

output "wiremock_url" {
  description = "URL for WireMock API (custom domain if set, otherwise shared ALB DNS)"
  value = (
    var.enable_wiremock
    ? (
      var.wiremock_domain_name != null
      ? "https://${var.wiremock_domain_name}"
      : try("https://${var.wiremock_alb_dns_name}", null)
    )
    : null
  )
}

output "wiremock_admin_url" {
  description = "URL for WireMock admin API"
  value = (
    var.enable_wiremock
    ? (
      var.wiremock_domain_name != null
      ? "https://${var.wiremock_domain_name}/__admin"
      : try("https://${var.wiremock_alb_dns_name}/__admin", null)
    )
    : null
  )
}
