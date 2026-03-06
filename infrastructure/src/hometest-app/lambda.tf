################################################################################
# Lambda Functions - Per-Lambda IAM with Least Privilege
#
# Each Lambda function gets its own dedicated IAM role with only the
# permissions it needs. Secrets, SQS queues, S3 buckets, DynamoDB tables,
# and Aurora clusters are granted individually per function via the `iam`
# block in the lambdas variable.
#
# Internal SQS queues can be referenced by name via `sqs_send_to` and
# `sqs_receive_from` fields - the Terraform code resolves them to ARNs.
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

  # ---------------------------------------------------------------------------
  # SQS Queue Name → ARN lookup (for sqs_send_to / sqs_receive_from fields)
  # ---------------------------------------------------------------------------
  sqs_queue_arns_by_name = {
    "events"          = length(local.sqs_lambdas) > 0 ? module.sqs_events[0].queue_arn : null
    "order-placement" = module.sqs_order_placement.queue_arn
    "order-results"   = module.sqs_order_results.queue_arn
    "notifications"   = module.sqs_notifications.queue_arn
  }
}

################################################################################
# Lambda Functions (official terraform-aws-modules/lambda/aws via wrapper)
################################################################################

module "lambdas" {
  source   = "../../modules/lambda"
  for_each = local.all_lambdas

  project_name          = var.project_name
  aws_account_shortname = var.aws_account_shortname
  function_name         = each.key
  environment           = var.environment

  # IAM: account & region for policy ARN construction
  aws_account_id = var.aws_account_id
  aws_region     = var.aws_region

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

  # ---------------------------------------------------------------------------
  # Per-Lambda IAM (least privilege)
  # ---------------------------------------------------------------------------

  enable_vpc_access = var.enable_vpc_access
  enable_xray       = true

  # Secrets — only the secrets this specific Lambda needs
  secrets_arns = try(each.value.iam.secrets_arns, [])

  # SSM Parameters
  ssm_parameter_arns = try(each.value.iam.ssm_parameter_arns, [])

  # KMS — always include the shared KMS key + any per-lambda keys
  kms_key_arns = distinct(compact(concat(
    var.kms_key_arn != null ? [var.kms_key_arn] : [],
    try(each.value.iam.kms_key_arns, [])
  )))

  # S3 buckets
  s3_bucket_arns = try(each.value.iam.s3_bucket_arns, [])

  # DynamoDB tables
  dynamodb_table_arns = try(each.value.iam.dynamodb_table_arns, [])

  # SQS Send — explicit ARNs + resolved internal queue names
  sqs_send_queue_arns = distinct(compact(concat(
    try(each.value.iam.sqs_send_queue_arns, []),
    [for q in try(each.value.sqs_send_to, []) : try(local.sqs_queue_arns_by_name[q], null)]
  )))

  # SQS Receive — explicit ARNs + resolved internal queue names + auto for sqs_trigger
  sqs_receive_queue_arns = distinct(compact(concat(
    try(each.value.iam.sqs_receive_queue_arns, []),
    [for q in try(each.value.sqs_receive_from, []) : try(local.sqs_queue_arns_by_name[q], null)],
    try(each.value.sqs_trigger, false) ? compact([try(local.sqs_queue_arns_by_name["events"], null)]) : []
  )))

  # Aurora IAM authentication
  aurora_cluster_resource_ids = try(each.value.iam.aurora_cluster_resource_ids, [])

  # Managed policies — always include CloudWatch Lambda Insights
  managed_policy_arns = distinct(concat(
    ["arn:aws:iam::aws:policy/CloudWatchLambdaInsightsExecutionRolePolicy"],
    try(each.value.iam.managed_policy_arns, [])
  ))

  custom_policies = try(each.value.iam.custom_policies, {})

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
