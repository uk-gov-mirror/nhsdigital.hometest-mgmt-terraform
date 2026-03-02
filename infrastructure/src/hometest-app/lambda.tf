################################################################################
# Lambda Functions - Dynamic Creation from Map
################################################################################

locals {
  all_lambdas = var.lambdas

  # Extract lambdas that have API Gateway integration
  api_lambdas = { for k, v in local.all_lambdas : k => v if v.api_path_prefix != null }

  # Compute zip paths for each lambda
  lambda_zip_paths = {
    for k, v in local.all_lambdas : k => coalesce(
      v.zip_path,
      "${var.lambdas_base_path}/${k}/${k}.zip"
    )
  }

  # Lambda Insights layer ARN — switches between x86_64 and arm64 based on var.lambda_architecture
  # https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Lambda-Insights-extension-versionsARM.html
  # https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Lambda-Insights-extension-versionsx86-64.html
  lambda_insights_layer_arn = var.lambda_architecture == "arm64" ? "arn:aws:lambda:eu-west-2:580247275435:layer:LambdaInsightsExtension-Arm64:31" : "arn:aws:lambda:eu-west-2:580247275435:layer:LambdaInsightsExtension:64"
}

################################################################################
# Lambda Functions
################################################################################

module "lambdas" {
  source   = "../../modules/lambda"
  for_each = local.all_lambdas

  project_name          = var.project_name
  aws_account_shortname = var.aws_account_shortname
  function_name         = each.key
  environment           = var.environment
  lambda_role_arn       = module.lambda_iam.role_arn

  # Deployment: local zip file (Terraform uploads) or placeholder
  use_placeholder = var.use_placeholder_lambda

  # When not using placeholder, use local zip file - Terraform uploads it directly
  filename = var.use_placeholder_lambda ? null : local.lambda_zip_paths[each.key]
  source_code_hash = var.use_placeholder_lambda ? null : (
    each.value.source_hash != null ? each.value.source_hash : (
      fileexists(local.lambda_zip_paths[each.key]) ? filebase64sha256(local.lambda_zip_paths[each.key]) : null
    )
  )

  description = each.value.description
  handler     = each.value.handler
  runtime     = coalesce(each.value.runtime, var.lambda_runtime)
  timeout     = coalesce(each.value.timeout, var.lambda_timeout)
  memory_size = coalesce(each.value.memory_size, var.lambda_memory_size)

  architectures = [var.lambda_architecture]
  layers        = [local.lambda_insights_layer_arn]

  tracing_mode       = "Active"
  log_retention_days = var.log_retention_days

  vpc_subnet_ids         = var.lambda_subnet_ids
  vpc_security_group_ids = var.lambda_security_group_ids

  lambda_kms_key_arn     = var.kms_key_arn
  cloudwatch_kms_key_arn = var.kms_key_arn

  alarm_actions = var.sns_alerts_topic_arn != null ? [var.sns_alerts_topic_arn] : []

  reserved_concurrent_executions = each.value.reserved_concurrent_executions

  environment_variables = merge(
    {
      NODE_OPTIONS = "--enable-source-maps"
      ENVIRONMENT  = var.environment
      LAMBDA_NAME  = each.key
    },
    each.value.environment
  )

  tags = local.common_tags
}

################################################################################
# Lambda Permissions for API Gateway
################################################################################

resource "aws_lambda_permission" "api_gateway" {
  for_each = local.api_lambdas

  statement_id  = "AllowAPIGatewayInvoke-${each.key}"
  action        = "lambda:InvokeFunction"
  function_name = module.lambdas[each.key].function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.apis[each.value.api_path_prefix].execution_arn}/*/*"
}

################################################################################
# Outputs for Lambda Functions
################################################################################

output "lambda_functions_detail" {
  description = "Map of Lambda function details"
  value = {
    for k, v in module.lambdas : k => {
      function_name = v.function_name
      function_arn  = v.function_arn
      invoke_arn    = v.function_invoke_arn
    }
  }
}
