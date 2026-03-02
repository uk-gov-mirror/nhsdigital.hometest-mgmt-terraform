################################################################################
# Lambda Execution IAM Role
################################################################################

locals {
  # Collect all secrets ARNs from lambda definitions
  lambda_secrets_from_map = compact([
    for k, v in local.all_lambdas : try(v.secrets_arn, null)
  ])

  # Combine with variable-provided secrets ARNs
  all_secrets_arns = distinct(concat(var.lambda_secrets_arns, local.lambda_secrets_from_map))

  # SQS queue ARNs — all queues always included so Lambda can send/receive from any of them
  sqs_queue_arns = distinct(concat(
    var.lambda_sqs_queue_arns,
    length(local.sqs_lambdas) > 0 ? [module.sqs_events[0].queue_arn] : [],
    [module.sqs_order_results.queue_arn],
    [module.sqs_order_placement.queue_arn],
    [module.sqs_notifications.queue_arn],
  ))
}

module "lambda_iam" {
  source = "../../modules/lambda-iam"

  project_name          = var.project_name
  environment           = var.environment
  aws_account_id        = var.aws_account_id
  aws_region            = var.aws_region
  aws_account_shortname = var.aws_account_shortname

  enable_xray       = true
  enable_vpc_access = var.enable_vpc_access
  vpc_id            = var.vpc_id

  secrets_arns       = local.all_secrets_arns
  ssm_parameter_arns = var.lambda_ssm_parameter_arns
  kms_key_arns = concat(
    var.kms_key_arn != null ? [var.kms_key_arn] : [],
    var.lambda_additional_kms_key_arns
  )
  # s3_bucket_arns      = concat([var.deployment_bucket_arn], var.lambda_s3_bucket_arns)
  s3_bucket_arns      = concat(var.lambda_s3_bucket_arns)
  dynamodb_table_arns = var.lambda_dynamodb_table_arns
  sqs_queue_arns      = local.sqs_queue_arns
  enable_sqs_access   = true # SQS queues are always created — avoids count-on-computed-value error

  aurora_cluster_resource_ids = var.lambda_aurora_cluster_resource_ids

  managed_policy_arns = [
    "arn:aws:iam::aws:policy/CloudWatchLambdaInsightsExecutionRolePolicy",
  ]

  tags = local.common_tags

  depends_on = [module.sqs_events, module.sqs_order_results, module.sqs_order_placement, module.sqs_notifications]
}
