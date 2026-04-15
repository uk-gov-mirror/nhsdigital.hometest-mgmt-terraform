################################################################################
# CloudFront Alarms Module
# CloudWatch alarms for CloudFront distribution metrics
# NOTE: CloudFront metrics are in us-east-1 — use provider alias
################################################################################

locals {
  resource_prefix = "${var.project_name}-${var.aws_account_shortname}-${var.environment}"

  common_tags = merge(
    var.tags,
    {
      Service      = "cloudfront-alarms"
      ManagedBy    = "terraform"
      Module       = "cloudfront-alarms"
      ResourceType = "cloudwatch-alarm"
    }
  )
}

################################################################################
# 5XX Error Rate Alarm
################################################################################

resource "aws_cloudwatch_metric_alarm" "cloudfront_5xx" {
  alarm_name          = "${local.resource_prefix}-cloudfront-5xx-high"
  alarm_description   = "CloudFront 5XX error rate exceeds ${var.alarm_5xx_threshold}%"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "5xxErrorRate"
  namespace           = "AWS/CloudFront"
  period              = var.alarm_period
  statistic           = "Average"
  threshold           = var.alarm_5xx_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    DistributionId = var.distribution_id
    Region         = "Global"
  }

  alarm_actions = var.alarm_actions
  ok_actions    = var.enable_ok_actions ? var.alarm_actions : []

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-cloudfront-5xx-high"
  })
}

################################################################################
# 4XX Error Rate Alarm
################################################################################

resource "aws_cloudwatch_metric_alarm" "cloudfront_4xx" {
  alarm_name          = "${local.resource_prefix}-cloudfront-4xx-high"
  alarm_description   = "CloudFront 4XX error rate exceeds ${var.alarm_4xx_threshold}%"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "4xxErrorRate"
  namespace           = "AWS/CloudFront"
  period              = var.alarm_period
  statistic           = "Average"
  threshold           = var.alarm_4xx_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    DistributionId = var.distribution_id
    Region         = "Global"
  }

  alarm_actions = var.alarm_actions
  ok_actions    = var.enable_ok_actions ? var.alarm_actions : []

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-cloudfront-4xx-high"
  })
}

################################################################################
# Origin Latency Alarm
################################################################################

resource "aws_cloudwatch_metric_alarm" "cloudfront_origin_latency" {
  count = var.create_origin_latency_alarm ? 1 : 0

  alarm_name          = "${local.resource_prefix}-cloudfront-origin-latency-high"
  alarm_description   = "CloudFront origin latency exceeds ${var.alarm_origin_latency_threshold_ms}ms"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "OriginLatency"
  namespace           = "AWS/CloudFront"
  period              = var.alarm_period
  extended_statistic  = "p99"
  threshold           = var.alarm_origin_latency_threshold_ms
  treat_missing_data  = "notBreaching"

  dimensions = {
    DistributionId = var.distribution_id
    Region         = "Global"
  }

  alarm_actions = var.alarm_actions
  ok_actions    = var.enable_ok_actions ? var.alarm_actions : []

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-cloudfront-origin-latency-high"
  })
}
