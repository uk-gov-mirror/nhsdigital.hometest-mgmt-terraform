################################################################################
# Lambda Module
# Deploys Lambda functions using the official terraform-aws-modules/lambda/aws
# module with per-function least-privilege IAM roles.
#
# Each Lambda gets its own dedicated IAM role (see iam.tf) with only the
# permissions it needs — secrets, SQS queues, S3 buckets, DynamoDB tables,
# Aurora clusters, etc. are granted individually per function.
################################################################################

locals {
  function_name = "${var.project_name}-${var.aws_account_shortname}-${var.environment}-${var.function_name}"

  # Placeholder code for initial deployment
  placeholder_code = <<EOF
exports.handler = async (event) => {
  return ${var.placeholder_response};
};
EOF

  common_tags = merge(
    var.tags,
    {
      Name         = local.function_name
      Service      = "lambda"
      Runtime      = var.runtime
      ManagedBy    = "terraform"
      Module       = "lambda"
      ResourceType = "lambda-function"
    }
  )
}

################################################################################
# Placeholder ZIP Archive (when use_placeholder is true)
################################################################################

data "archive_file" "placeholder" {
  count = var.use_placeholder ? 1 : 0

  type        = "zip"
  output_path = "${path.module}/.placeholder/${local.function_name}.zip"

  source {
    content  = local.placeholder_code
    filename = "index.js"
  }
}

################################################################################
# Lambda Function (official terraform-aws-modules/lambda/aws)
################################################################################

module "lambda" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "8.7.0"

  function_name = local.function_name
  description   = var.description
  handler       = var.handler
  runtime       = var.runtime
  timeout       = var.timeout
  memory_size   = var.memory_size
  architectures = var.architectures
  layers        = length(var.layers) > 0 ? var.layers : null
  publish       = var.publish

  # Use our per-lambda IAM role (least privilege) — see iam.tf
  create_role = false
  lambda_role = aws_iam_role.this.arn

  # Deployment package — we always provide the package ourselves
  create_package = false

  local_existing_package = (
    var.use_placeholder ? data.archive_file.placeholder[0].output_path :
    var.filename != null ? var.filename :
    null
  )

  s3_existing_package = (
    !var.use_placeholder && var.filename == null && var.s3_bucket != null ? {
      bucket     = var.s3_bucket
      key        = var.s3_key
      version_id = var.s3_object_version
    } : null
  )

  hash_extra = var.source_code_hash

  # VPC Configuration
  vpc_subnet_ids         = var.vpc_subnet_ids
  vpc_security_group_ids = var.vpc_security_group_ids

  # Environment variables
  environment_variables = var.environment_variables

  # X-Ray tracing
  tracing_mode = var.tracing_mode

  # Encryption for environment variables at rest
  kms_key_arn = var.lambda_kms_key_arn

  # Reserved concurrency (-1 = unreserved)
  reserved_concurrent_executions = var.reserved_concurrent_executions

  # CloudWatch Logs (module creates log group automatically)
  cloudwatch_logs_retention_in_days = var.log_retention_days
  cloudwatch_logs_kms_key_id        = var.cloudwatch_kms_key_arn

  # Dead letter queue
  dead_letter_target_arn = var.dead_letter_target_arn

  tags = local.common_tags

  timeouts = {
    create = "10m"
    update = "10m"
    delete = "10m"
  }
}

################################################################################
# CloudWatch Alarm - Lambda Errors (Failed Invocations)
################################################################################

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  count = var.create_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${local.function_name}-errors-high"
  alarm_description   = "Alert when Lambda function reports errors (failed invocations)"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = var.alarm_period
  statistic           = "Sum"
  threshold           = var.alarm_error_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = module.lambda.lambda_function_name
  }

  alarm_actions = var.alarm_actions
  ok_actions    = var.alarm_actions

  tags = merge(local.common_tags, {
    ResourceType = "cloudwatch-alarm"
  })
}
