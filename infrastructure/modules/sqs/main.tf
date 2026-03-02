################################################################################
# SQS Module
# AWS SQS queues with DLQ, encryption, and monitoring best practices
################################################################################

locals {
  queue_name = "${var.project_name}-${var.aws_account_shortname}-${var.environment}-${var.queue_name_suffix}"
  dlq_name   = var.create_dlq ? "${local.queue_name}-dlq" : null

  common_tags = merge(
    var.tags,
    {
      Name         = local.queue_name
      Service      = "sqs"
      ManagedBy    = "terraform"
      Module       = "sqs"
      ResourceType = "queue"
    }
  )

  dlq_tags = merge(
    var.tags,
    {
      Name         = local.dlq_name
      Service      = "sqs"
      ManagedBy    = "terraform"
      Module       = "sqs"
      ResourceType = "dlq"
    }
  )
}

################################################################################
# Dead Letter Queue (DLQ)
################################################################################

module "dlq" {
  count   = var.create_dlq ? 1 : 0
  source  = "terraform-aws-modules/sqs/aws"
  version = "~> 5.2.1"

  name                        = local.dlq_name
  fifo_queue                  = var.fifo_queue
  content_based_deduplication = var.fifo_queue ? var.content_based_deduplication : null

  # Encryption
  kms_master_key_id                 = var.kms_master_key_id
  kms_data_key_reuse_period_seconds = var.kms_data_key_reuse_period_seconds
  sqs_managed_sse_enabled           = var.sqs_managed_sse_enabled

  # Message retention
  message_retention_seconds = var.dlq_message_retention_seconds

  tags = local.dlq_tags
}

################################################################################
# Main SQS Queue
################################################################################

module "queue" {
  source  = "terraform-aws-modules/sqs/aws"
  version = "~> 5.2.1"

  name                        = local.queue_name
  fifo_queue                  = var.fifo_queue
  content_based_deduplication = var.fifo_queue ? var.content_based_deduplication : null
  deduplication_scope         = var.fifo_queue ? var.deduplication_scope : null
  fifo_throughput_limit       = var.fifo_queue ? var.fifo_throughput_limit : null

  # Encryption
  kms_master_key_id                 = var.kms_master_key_id
  kms_data_key_reuse_period_seconds = var.kms_data_key_reuse_period_seconds
  sqs_managed_sse_enabled           = var.sqs_managed_sse_enabled

  # Message configuration
  visibility_timeout_seconds = var.visibility_timeout_seconds
  message_retention_seconds  = var.message_retention_seconds
  max_message_size           = var.max_message_size
  delay_seconds              = var.delay_seconds
  receive_wait_time_seconds  = var.receive_wait_time_seconds

  # Dead Letter Queue configuration
  redrive_policy = var.create_dlq ? {
    deadLetterTargetArn = module.dlq[0].queue_arn
    maxReceiveCount     = var.max_receive_count
  } : null

  # Allow dead letter queue redrive (for reprocessing messages from DLQ)
  redrive_allow_policy = var.create_dlq && var.enable_dlq_redrive ? {
    redrivePermission = "byQueue"
    sourceQueueArns   = [module.dlq[0].queue_arn]
  } : null

  # Access policy
  create_queue_policy     = var.create_queue_policy
  queue_policy_statements = var.queue_policy_statements

  tags = local.common_tags
}

################################################################################
# CloudWatch Alarms for Queue Monitoring
################################################################################

resource "aws_cloudwatch_metric_alarm" "queue_age" {
  count = var.create_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${local.queue_name}-age-high"
  alarm_description   = "Alert when oldest message age exceeds threshold"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "ApproximateAgeOfOldestMessage"
  namespace           = "AWS/SQS"
  period              = var.alarm_period
  statistic           = "Maximum"
  threshold           = var.alarm_age_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = module.queue.queue_name
  }

  alarm_actions = var.alarm_actions
  ok_actions    = var.alarm_actions

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "queue_depth" {
  count = var.create_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${local.queue_name}-depth-high"
  alarm_description   = "Alert when queue depth exceeds threshold"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = var.alarm_period
  statistic           = "Average"
  threshold           = var.alarm_depth_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = module.queue.queue_name
  }

  alarm_actions = var.alarm_actions
  ok_actions    = var.alarm_actions

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "dlq_depth" {
  count = var.create_dlq && var.create_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${local.dlq_name}-depth-high"
  alarm_description   = "Alert when DLQ has messages"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Average"
  threshold           = var.alarm_dlq_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = module.dlq[0].queue_name
  }

  alarm_actions = var.alarm_actions
  ok_actions    = var.alarm_actions

  tags = local.dlq_tags
}
