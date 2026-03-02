################################################################################
# SQS Queues and Lambda Event Source Mapping
# Uses terraform-aws-modules/sqs/aws (via local modules/sqs wrapper) for all queues.
################################################################################

locals {
  # Find lambdas that need SQS triggers
  sqs_lambdas = { for k, v in local.all_lambdas : k => v if try(v.sqs_trigger, false) }
}

################################################################################
# Order Placement Queue
# Written to by order-service-lambda; consumed by order-router-lambda (SQS trigger)
################################################################################

module "sqs_order_placement" {
  source = "../../modules/sqs"

  project_name          = var.project_name
  aws_account_shortname = var.aws_account_shortname
  environment           = var.environment
  queue_name_suffix     = "order-placement"

  visibility_timeout_seconds = 300     # 5 min — allow time for order-router-lambda (60 s timeout × 5)
  message_retention_seconds  = 1209600 # 14 days
  receive_wait_time_seconds  = 20      # Long polling

  create_dlq        = true
  max_receive_count = 3

  kms_master_key_id       = var.kms_key_arn
  sqs_managed_sse_enabled = false

  create_cloudwatch_alarms = true
  alarm_actions            = [var.sns_alerts_topic_arn]

  tags = local.common_tags
}

################################################################################
# Order Results Queue
# Written to by order-result-lambda
################################################################################

module "sqs_order_results" {
  source = "../../modules/sqs"

  project_name          = var.project_name
  aws_account_shortname = var.aws_account_shortname
  environment           = var.environment
  queue_name_suffix     = "order-results"

  visibility_timeout_seconds = 300     # 5 minutes
  message_retention_seconds  = 1209600 # 14 days
  receive_wait_time_seconds  = 20      # Long polling

  create_dlq        = true
  max_receive_count = 3

  kms_master_key_id       = var.kms_key_arn
  sqs_managed_sse_enabled = false

  create_cloudwatch_alarms = true
  alarm_actions            = [var.sns_alerts_topic_arn]

  tags = local.common_tags
}

################################################################################
# Notifications Queue (FIFO)
# For reliable, ordered notification delivery
################################################################################

module "sqs_notifications" {
  source = "../../modules/sqs"

  project_name          = var.project_name
  aws_account_shortname = var.aws_account_shortname
  environment           = var.environment
  queue_name_suffix     = "notifications"

  # FIFO configuration
  fifo_queue                  = true
  content_based_deduplication = true
  deduplication_scope         = "messageGroup"
  fifo_throughput_limit       = "perMessageGroupId"

  visibility_timeout_seconds = 180    # 3 minutes
  message_retention_seconds  = 345600 # 4 days
  receive_wait_time_seconds  = 20     # Long polling

  create_dlq        = true
  max_receive_count = 3

  kms_master_key_id       = var.kms_key_arn
  sqs_managed_sse_enabled = false

  create_cloudwatch_alarms = true
  alarm_actions            = [var.sns_alerts_topic_arn]

  tags = local.common_tags
}

################################################################################
# Events Queue
# Triggers lambdas with sqs_trigger = true (e.g., order-router-lambda)
################################################################################

module "sqs_events" {
  count  = length(local.sqs_lambdas) > 0 ? 1 : 0
  source = "../../modules/sqs"

  project_name          = var.project_name
  aws_account_shortname = var.aws_account_shortname
  environment           = var.environment
  queue_name_suffix     = "events"

  visibility_timeout_seconds = 300     # Should be >= 6× the Lambda timeout (60 s × 6 = 360)
  message_retention_seconds  = 1209600 # 14 days
  receive_wait_time_seconds  = 20      # Long polling

  create_dlq        = true
  max_receive_count = 3

  kms_master_key_id       = var.kms_key_arn
  sqs_managed_sse_enabled = false

  # Allow Lambda service to receive/delete messages from this queue
  create_queue_policy = true
  queue_policy_statements = {
    AllowLambdaToReceive = {
      sid    = "AllowLambdaToReceive"
      effect = "Allow"
      principals = [
        { type = "Service", identifiers = ["lambda.amazonaws.com"] }
      ]
      actions = [
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:GetQueueAttributes",
      ]
      conditions = [
        {
          test     = "ArnLike"
          variable = "aws:SourceArn"
          values   = ["arn:aws:lambda:${var.aws_region}:${var.aws_account_id}:function:${local.resource_prefix}-*"]
        }
      ]
    }
  }

  create_cloudwatch_alarms = true
  alarm_actions            = [var.sns_alerts_topic_arn]

  tags = local.common_tags
}

################################################################################
# Lambda Event Source Mapping for SQS
################################################################################

resource "aws_lambda_event_source_mapping" "sqs" {
  for_each = local.sqs_lambdas

  event_source_arn = module.sqs_events[0].queue_arn
  function_name    = module.lambdas[each.key].function_arn
  enabled          = true

  batch_size                         = 10
  maximum_batching_window_in_seconds = 5

  # Enable partial batch failure reporting
  function_response_types = ["ReportBatchItemFailures"]

  # Scaling configuration
  scaling_config {
    maximum_concurrency = 10
  }
}

################################################################################
# Dedicated Event Source Mapping for Order Router Lambda
# Connects order-router-lambda to the order_placement queue
################################################################################

resource "aws_lambda_event_source_mapping" "order_router_order_placement" {
  count = contains(keys(var.lambdas), "order-router-lambda") ? 1 : 0

  event_source_arn = module.sqs_order_placement.queue_arn
  function_name    = module.lambdas["order-router-lambda"].function_arn
  enabled          = true
  batch_size       = 1

  # Enable partial batch failure reporting
  function_response_types = ["ReportBatchItemFailures"]
}

################################################################################
# Outputs
################################################################################

output "sqs_queue_url" {
  description = "URL of the events SQS queue"
  value       = length(local.sqs_lambdas) > 0 ? module.sqs_events[0].queue_url : null
}

output "sqs_queue_arn" {
  description = "ARN of the events SQS queue"
  value       = length(local.sqs_lambdas) > 0 ? module.sqs_events[0].queue_arn : null
}

output "sqs_dlq_url" {
  description = "URL of the events dead letter queue"
  value       = length(local.sqs_lambdas) > 0 ? module.sqs_events[0].dlq_url : null
}

output "sqs_dlq_arn" {
  description = "ARN of the events dead letter queue"
  value       = length(local.sqs_lambdas) > 0 ? module.sqs_events[0].dlq_arn : null
}

output "order_results_queue_url" {
  description = "URL of the order results SQS queue"
  value       = module.sqs_order_results.queue_url
}

output "order_results_queue_arn" {
  description = "ARN of the order results SQS queue"
  value       = module.sqs_order_results.queue_arn
}

output "notifications_queue_url" {
  description = "URL of the notifications SQS queue (FIFO)"
  value       = module.sqs_notifications.queue_url
}

output "notifications_queue_arn" {
  description = "ARN of the notifications SQS queue (FIFO)"
  value       = module.sqs_notifications.queue_arn
}

output "notifications_dlq_url" {
  description = "URL of the notifications dead letter queue"
  value       = module.sqs_notifications.dlq_url
}

output "notifications_dlq_arn" {
  description = "ARN of the notifications dead letter queue"
  value       = module.sqs_notifications.dlq_arn
}

output "order_placement_queue_url" {
  description = "URL of the order placement SQS queue"
  value       = module.sqs_order_placement.queue_url
}

output "order_placement_queue_arn" {
  description = "ARN of the order placement SQS queue"
  value       = module.sqs_order_placement.queue_arn
}
