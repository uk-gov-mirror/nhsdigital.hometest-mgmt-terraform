################################################################################
# API Gateways - Dynamic Creation from Lambda Map
# Each lambda with api_path_prefix gets its own API Gateway
################################################################################

locals {
  # Get unique API path prefixes from lambdas
  api_prefixes = toset([for k, v in local.api_lambdas : v.api_path_prefix])

  # Map of api_prefix to lambda name (for integration)
  api_to_lambda = { for k, v in local.api_lambdas : v.api_path_prefix => k }

  authorized_api_prefixes = var.authorized_api_prefixes
}

################################################################################
# API Gateway REST APIs
################################################################################

resource "aws_api_gateway_rest_api" "apis" {
  for_each = local.api_prefixes

  name        = "${local.resource_prefix}-${each.key}"
  description = "API Gateway for ${each.key} - ${var.project_name} ${var.environment}"

  endpoint_configuration {
    types = [var.api_endpoint_type]
  }

  tags = merge(local.common_tags, {
    Name      = "${local.resource_prefix}-${each.key}"
    ApiPrefix = each.key
  })
}

################################################################################
# API Gateway Resources and Methods (Proxy Integration)
################################################################################

# Proxy resource for catch-all routing
resource "aws_api_gateway_resource" "proxy" {
  for_each = local.api_prefixes

  rest_api_id = aws_api_gateway_rest_api.apis[each.key].id
  parent_id   = aws_api_gateway_rest_api.apis[each.key].root_resource_id
  path_part   = "{proxy+}"
}

# ANY method on proxy resource
resource "aws_api_gateway_method" "proxy_any" {
  for_each = local.api_prefixes

  rest_api_id = aws_api_gateway_rest_api.apis[each.key].id
  resource_id = aws_api_gateway_resource.proxy[each.key].id
  http_method = "ANY"

  # Apply authorization if this API prefix is in authorized list
  authorization = contains(local.authorized_api_prefixes, each.key) ? "COGNITO_USER_POOLS" : "NONE"
  authorizer_id = contains(local.authorized_api_prefixes, each.key) ? aws_api_gateway_authorizer.cognito_supplier[each.key].id : null

  # Authorization scopes
  authorization_scopes = (
    contains(local.authorized_api_prefixes, each.key) &&
    lookup(local.api_lambdas[local.api_to_lambda[each.key]], "authorization_scopes", null) != null
  ) ? local.api_lambdas[local.api_to_lambda[each.key]].authorization_scopes : null
}

# Lambda integration for proxy
resource "aws_api_gateway_integration" "proxy" {
  for_each = local.api_prefixes

  rest_api_id             = aws_api_gateway_rest_api.apis[each.key].id
  resource_id             = aws_api_gateway_resource.proxy[each.key].id
  http_method             = aws_api_gateway_method.proxy_any[each.key].http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = module.lambdas[local.api_to_lambda[each.key]].function_invoke_arn
}

# ANY method on root
resource "aws_api_gateway_method" "root" {
  for_each = local.api_prefixes

  rest_api_id = aws_api_gateway_rest_api.apis[each.key].id
  resource_id = aws_api_gateway_rest_api.apis[each.key].root_resource_id
  http_method = "ANY"

  # Apply authorization if this API prefix is in authorized list
  authorization = contains(local.authorized_api_prefixes, each.key) ? "COGNITO_USER_POOLS" : "NONE"
  authorizer_id = contains(local.authorized_api_prefixes, each.key) ? aws_api_gateway_authorizer.cognito_supplier[each.key].id : null

  authorization_scopes = (
    contains(local.authorized_api_prefixes, each.key) &&
    lookup(local.api_lambdas[local.api_to_lambda[each.key]], "authorization_scopes", null) != null
  ) ? local.api_lambdas[local.api_to_lambda[each.key]].authorization_scopes : null
}

# Lambda integration for root
resource "aws_api_gateway_integration" "root" {
  for_each = local.api_prefixes

  rest_api_id             = aws_api_gateway_rest_api.apis[each.key].id
  resource_id             = aws_api_gateway_rest_api.apis[each.key].root_resource_id
  http_method             = aws_api_gateway_method.root[each.key].http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = module.lambdas[local.api_to_lambda[each.key]].function_invoke_arn
}

################################################################################
# Cognito Supplier Authorizer
################################################################################

resource "aws_api_gateway_authorizer" "cognito_supplier" {
  for_each = toset(local.authorized_api_prefixes)

  name            = "${var.project_name}-${var.environment}-${each.key}-supplier-cognito-authorizer"
  rest_api_id     = aws_api_gateway_rest_api.apis[each.key].id
  type            = "COGNITO_USER_POOLS"
  provider_arns   = [var.cognito_user_pool_arn]
  identity_source = "method.request.header.Authorization"
}

################################################################################
# CORS configuration
#
# Two levels need OPTIONS handlers:
#   1. Root resource (/)       — hit when the URL matches the base_path exactly
#   2. Proxy resource ({proxy+}) — hit for any sub-path
#
# Additionally, DEFAULT_4XX and DEFAULT_5XX gateway responses include CORS
# headers so that API Gateway-generated errors (throttle, auth failure, etc.)
# are not swallowed by the browser's Same-Origin Policy.
################################################################################

locals {
  cors_origin = var.cors_allowed_origin != null ? var.cors_allowed_origin : "*"
}

# --- {proxy+} OPTIONS --------------------------------------------------------
# NOSONAR: OPTIONS methods must use authorization=NONE — browsers send
# unauthenticated CORS preflight requests that cannot carry auth headers.
# The API is protected by WAF (aws_wafv2_web_acl_association.apis) and
# Cognito authorizers on all non-OPTIONS methods.

resource "aws_api_gateway_method" "options" {
  for_each = local.api_prefixes

  rest_api_id   = aws_api_gateway_rest_api.apis[each.key].id
  resource_id   = aws_api_gateway_resource.proxy[each.key].id
  http_method   = "OPTIONS"
  authorization = "NONE" # NOSONAR — CORS preflight; WAF protects the stage
}

resource "aws_api_gateway_integration" "options" {
  for_each = local.api_prefixes

  rest_api_id = aws_api_gateway_rest_api.apis[each.key].id
  resource_id = aws_api_gateway_resource.proxy[each.key].id
  http_method = aws_api_gateway_method.options[each.key].http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = jsonencode({ statusCode = 200 })
  }
}

resource "aws_api_gateway_method_response" "options" {
  for_each = local.api_prefixes

  rest_api_id = aws_api_gateway_rest_api.apis[each.key].id
  resource_id = aws_api_gateway_resource.proxy[each.key].id
  http_method = aws_api_gateway_method.options[each.key].http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers"     = true
    "method.response.header.Access-Control-Allow-Methods"     = true
    "method.response.header.Access-Control-Allow-Origin"      = true
    "method.response.header.Access-Control-Allow-Credentials" = true
  }
}

resource "aws_api_gateway_integration_response" "options" {
  for_each = local.api_prefixes

  rest_api_id = aws_api_gateway_rest_api.apis[each.key].id
  resource_id = aws_api_gateway_resource.proxy[each.key].id
  http_method = aws_api_gateway_method.options[each.key].http_method
  status_code = aws_api_gateway_method_response.options[each.key].status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers"     = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token,x-correlation-id'"
    "method.response.header.Access-Control-Allow-Methods"     = "'GET,POST,PUT,DELETE,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"      = "'${local.cors_origin}'"
    "method.response.header.Access-Control-Allow-Credentials" = "'true'"
  }

  depends_on = [aws_api_gateway_integration.options]
}

# --- Root (/) OPTIONS --------------------------------------------------------
# NOSONAR: Same as {proxy+} OPTIONS above — CORS preflight requires no auth.

resource "aws_api_gateway_method" "root_options" {
  for_each = local.api_prefixes

  rest_api_id   = aws_api_gateway_rest_api.apis[each.key].id
  resource_id   = aws_api_gateway_rest_api.apis[each.key].root_resource_id
  http_method   = "OPTIONS"
  authorization = "NONE" # NOSONAR — CORS preflight; WAF protects the stage
}

resource "aws_api_gateway_integration" "root_options" {
  for_each = local.api_prefixes

  rest_api_id = aws_api_gateway_rest_api.apis[each.key].id
  resource_id = aws_api_gateway_rest_api.apis[each.key].root_resource_id
  http_method = aws_api_gateway_method.root_options[each.key].http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = jsonencode({ statusCode = 200 })
  }
}

resource "aws_api_gateway_method_response" "root_options" {
  for_each = local.api_prefixes

  rest_api_id = aws_api_gateway_rest_api.apis[each.key].id
  resource_id = aws_api_gateway_rest_api.apis[each.key].root_resource_id
  http_method = aws_api_gateway_method.root_options[each.key].http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers"     = true
    "method.response.header.Access-Control-Allow-Methods"     = true
    "method.response.header.Access-Control-Allow-Origin"      = true
    "method.response.header.Access-Control-Allow-Credentials" = true
  }
}

resource "aws_api_gateway_integration_response" "root_options" {
  for_each = local.api_prefixes

  rest_api_id = aws_api_gateway_rest_api.apis[each.key].id
  resource_id = aws_api_gateway_rest_api.apis[each.key].root_resource_id
  http_method = aws_api_gateway_method.root_options[each.key].http_method
  status_code = aws_api_gateway_method_response.root_options[each.key].status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers"     = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token,x-correlation-id'"
    "method.response.header.Access-Control-Allow-Methods"     = "'GET,POST,PUT,DELETE,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"      = "'${local.cors_origin}'"
    "method.response.header.Access-Control-Allow-Credentials" = "'true'"
  }

  depends_on = [aws_api_gateway_integration.root_options]
}

################################################################################
# Gateway Responses — CORS headers on API Gateway-generated errors
# Without these, 4xx/5xx from API Gateway itself (auth failures, throttles,
# missing routes) are blocked by the browser's Same-Origin Policy.
################################################################################

resource "aws_api_gateway_gateway_response" "default_4xx" {
  for_each = local.api_prefixes

  rest_api_id   = aws_api_gateway_rest_api.apis[each.key].id
  response_type = "DEFAULT_4XX"

  response_parameters = {
    "gatewayresponse.header.Access-Control-Allow-Origin"      = "'${local.cors_origin}'"
    "gatewayresponse.header.Access-Control-Allow-Headers"     = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
    "gatewayresponse.header.Access-Control-Allow-Methods"     = "'GET,POST,PUT,DELETE,OPTIONS'"
    "gatewayresponse.header.Access-Control-Allow-Credentials" = "'true'"
  }

  # Explicitly set the default response body so Terraform doesn't try to remove
  # the template that API Gateway creates automatically.
  response_templates = {
    "application/json" = "{\"message\":$context.error.messageString}"
  }
}

resource "aws_api_gateway_gateway_response" "default_5xx" {
  for_each = local.api_prefixes

  rest_api_id   = aws_api_gateway_rest_api.apis[each.key].id
  response_type = "DEFAULT_5XX"

  response_parameters = {
    "gatewayresponse.header.Access-Control-Allow-Origin"      = "'${local.cors_origin}'"
    "gatewayresponse.header.Access-Control-Allow-Headers"     = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
    "gatewayresponse.header.Access-Control-Allow-Methods"     = "'GET,POST,PUT,DELETE,OPTIONS'"
    "gatewayresponse.header.Access-Control-Allow-Credentials" = "'true'"
  }

  # Explicitly set the default response body so Terraform doesn't try to remove
  # the template that API Gateway creates automatically.
  response_templates = {
    "application/json" = "{\"message\":$context.error.messageString}"
  }
}

################################################################################
# API Gateway Stages
################################################################################

resource "aws_api_gateway_stage" "apis" {
  for_each = local.api_prefixes

  deployment_id = aws_api_gateway_deployment.apis[each.key].id
  rest_api_id   = aws_api_gateway_rest_api.apis[each.key].id
  stage_name    = var.api_stage_name

  xray_tracing_enabled = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway[each.key].arn
    format = jsonencode({
      requestId          = "$context.requestId"
      ip                 = "$context.identity.sourceIp"
      requestTime        = "$context.requestTime"
      httpMethod         = "$context.httpMethod"
      routeKey           = "$context.routeKey"
      status             = "$context.status"
      protocol           = "$context.protocol"
      responseLength     = "$context.responseLength"
      integrationError   = "$context.integrationErrorMessage"
      errorMessage       = "$context.error.message"
      integrationLatency = "$context.integrationLatency"
    })
  }

  tags = merge(local.common_tags, {
    Name      = "${local.resource_prefix}-${each.key}-${var.api_stage_name}"
    ApiPrefix = each.key
  })
}

################################################################################
# API Gateway CloudWatch Log Groups
################################################################################

resource "aws_cloudwatch_log_group" "api_gateway" {
  for_each = local.api_prefixes

  name              = "/aws/apigateway/${local.resource_prefix}-${each.key}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn

  tags = merge(local.common_tags, {
    Name      = "${local.resource_prefix}-${each.key}-logs"
    ApiPrefix = each.key
  })
}

################################################################################
# API Gateway Deployments
################################################################################

resource "aws_api_gateway_deployment" "apis" {
  for_each = local.api_prefixes

  rest_api_id = aws_api_gateway_rest_api.apis[each.key].id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.proxy[each.key].id,
      aws_api_gateway_method.proxy_any[each.key].id,
      aws_api_gateway_method.proxy_any[each.key].authorization,
      aws_api_gateway_method.proxy_any[each.key].authorizer_id,
      aws_api_gateway_method.root[each.key].id,
      aws_api_gateway_method.root[each.key].authorization,
      aws_api_gateway_method.root[each.key].authorizer_id,
      aws_api_gateway_integration.proxy[each.key].id,
      aws_api_gateway_integration.root[each.key].id,
      aws_api_gateway_method.options[each.key].id,
      aws_api_gateway_method.root_options[each.key].id,
      aws_api_gateway_integration_response.options[each.key].id,
      aws_api_gateway_integration_response.options[each.key].response_parameters,
      aws_api_gateway_integration_response.root_options[each.key].id,
      aws_api_gateway_integration_response.root_options[each.key].response_parameters,
      aws_api_gateway_gateway_response.default_4xx[each.key].id,
      aws_api_gateway_gateway_response.default_4xx[each.key].response_parameters,
      aws_api_gateway_gateway_response.default_5xx[each.key].id,
      aws_api_gateway_gateway_response.default_5xx[each.key].response_parameters,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_api_gateway_integration.proxy,
    aws_api_gateway_integration.root,
    aws_api_gateway_integration.options,
    aws_api_gateway_integration.root_options,
    aws_api_gateway_gateway_response.default_4xx,
    aws_api_gateway_gateway_response.default_5xx,
  ]
}

################################################################################
# WAF Web ACL Association (one per stage)
################################################################################

resource "aws_wafv2_web_acl_association" "apis" {
  for_each = var.waf_regional_arn != null ? local.api_prefixes : toset([])

  # Stage ARN format for REST API: arn:aws:apigateway:{region}::/restapis/{id}/stages/{stage}
  resource_arn = "arn:aws:apigateway:${var.aws_region}::/restapis/${aws_api_gateway_rest_api.apis[each.key].id}/stages/${aws_api_gateway_stage.apis[each.key].stage_name}"
  web_acl_arn  = var.waf_regional_arn

  depends_on = [aws_api_gateway_stage.apis]
}

################################################################################
# API Gateway Method Settings (Throttling)
################################################################################

resource "aws_api_gateway_method_settings" "apis" {
  for_each = local.api_prefixes

  rest_api_id = aws_api_gateway_rest_api.apis[each.key].id
  stage_name  = aws_api_gateway_stage.apis[each.key].stage_name
  method_path = "*/*"

  settings {
    throttling_burst_limit = var.api_throttling_burst_limit
    throttling_rate_limit  = var.api_throttling_rate_limit
    metrics_enabled        = true
    logging_level          = "INFO"
    data_trace_enabled     = false # Don't log request/response data
  }
}

################################################################################
# API Gateway Custom Domain
#
# Two supported patterns (controlled by var.create_api_certificate):
#
#   POC / wildcard  (create_api_certificate = false):
#     Shared cert:  *.poc.hometest.service.nhs.uk  (from shared_services)
#     API domain:   api-dev.poc.hometest.service.nhs.uk  ← single-level, covered
#
#   Custom cert     (create_api_certificate = true):
#     Dedicated cert created here for api.dev.hometest.service.nhs.uk
#     (*.hometest.service.nhs.uk does NOT cover two-level subdomains)
################################################################################

locals {
  # Certificate ARN for the API Gateway custom domain.
  # When create_api_certificate = true a dedicated cert is created and validated here;
  # otherwise re-use the shared wildcard cert passed in from shared_services.
  api_cert_arn = (
    var.create_api_certificate
    ? try(aws_acm_certificate_validation.api_domain[0].certificate_arn, null)
    : var.acm_regional_certificate_arn
  )
}

# Dedicated regional ACM certificate — only created when create_api_certificate = true
resource "aws_acm_certificate" "api_domain" {
  count = var.api_custom_domain_name != null && var.create_api_certificate ? 1 : 0

  domain_name       = var.api_custom_domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-api-domain-cert"
  })
}

resource "aws_route53_record" "api_domain_cert_validation" {
  for_each = var.api_custom_domain_name != null && var.create_api_certificate ? {
    for dvo in aws_acm_certificate.api_domain[0].domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  } : {}

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = var.route53_zone_id
}

resource "aws_acm_certificate_validation" "api_domain" {
  count = var.api_custom_domain_name != null && var.create_api_certificate ? 1 : 0

  certificate_arn         = aws_acm_certificate.api_domain[0].arn
  validation_record_fqdns = [for record in aws_route53_record.api_domain_cert_validation : record.fqdn]
}

# Regional custom domain — one domain, multiple base path mappings (one per API prefix)
resource "aws_api_gateway_domain_name" "api" {
  count = var.api_custom_domain_name != null ? 1 : 0

  domain_name              = var.api_custom_domain_name
  regional_certificate_arn = local.api_cert_arn
  security_policy          = "TLS_1_2"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  dynamic "mutual_tls_authentication" {
    for_each = var.api_mutual_tls_truststore_uri != null ? [1] : []
    content {
      truststore_uri     = var.api_mutual_tls_truststore_uri
      truststore_version = var.api_mutual_tls_truststore_version
    }
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-api-custom-domain"
  })
}

# Base path mapping: https://{api_custom_domain_name}/{prefix}/... → REST API {prefix} stage v1
resource "aws_api_gateway_base_path_mapping" "api" {
  for_each = var.api_custom_domain_name != null ? local.api_prefixes : toset([])

  api_id      = aws_api_gateway_rest_api.apis[each.key].id
  stage_name  = aws_api_gateway_stage.apis[each.key].stage_name
  domain_name = aws_api_gateway_domain_name.api[0].domain_name
  base_path   = each.key

  depends_on = [aws_api_gateway_domain_name.api]
}

# Route53 alias record: {api_custom_domain_name} → API Gateway regional endpoint
resource "aws_route53_record" "api_domain" {
  count = var.api_custom_domain_name != null ? 1 : 0

  zone_id = var.route53_zone_id
  name    = var.api_custom_domain_name
  type    = "A"

  alias {
    name                   = aws_api_gateway_domain_name.api[0].regional_domain_name
    zone_id                = aws_api_gateway_domain_name.api[0].regional_zone_id
    evaluate_target_health = false
  }
}
