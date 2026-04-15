################################################################################
# API Gateway Alarms Module
# CloudWatch alarms for API Gateway REST API metrics
################################################################################

locals {
  resource_prefix = "${var.project_name}-${var.aws_account_shortname}-${var.environment}"

  common_tags = merge(
    var.tags,
    {
      Service      = "api-gateway-alarms"
      ManagedBy    = "terraform"
      Module       = "api-gateway-alarms"
      ResourceType = "cloudwatch-alarm"
    }
  )
}

################################################################################
# 5XX Error Rate Alarm
################################################################################

resource "aws_cloudwatch_metric_alarm" "api_5xx" {
  for_each = var.api_names

  alarm_name          = "${each.value}-5xx-high"
  alarm_description   = "API Gateway ${each.value} 5XX error rate exceeds ${var.alarm_5xx_threshold}%"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  threshold           = var.alarm_5xx_threshold
  treat_missing_data  = "notBreaching"

  metric_query {
    id          = "error_rate"
    expression  = "(errors / requests) * 100"
    label       = "5XX Error Rate %"
    return_data = true
  }

  metric_query {
    id = "errors"
    metric {
      metric_name = "5XXError"
      namespace   = "AWS/ApiGateway"
      period      = var.alarm_period
      stat        = "Sum"
      dimensions = {
        ApiName = each.value
      }
    }
  }

  metric_query {
    id = "requests"
    metric {
      metric_name = "Count"
      namespace   = "AWS/ApiGateway"
      period      = var.alarm_period
      stat        = "Sum"
      dimensions = {
        ApiName = each.value
      }
    }
  }

  alarm_actions = var.alarm_actions
  ok_actions    = var.enable_ok_actions ? var.alarm_actions : []

  tags = merge(local.common_tags, {
    Name      = "${each.value}-5xx-high"
    ApiPrefix = each.value
  })
}

################################################################################
# 4XX Error Rate Alarm
################################################################################

resource "aws_cloudwatch_metric_alarm" "api_4xx" {
  for_each = var.api_names

  alarm_name          = "${each.value}-4xx-high"
  alarm_description   = "API Gateway ${each.value} 4XX error rate exceeds ${var.alarm_4xx_threshold}%"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  threshold           = var.alarm_4xx_threshold
  treat_missing_data  = "notBreaching"

  metric_query {
    id          = "error_rate"
    expression  = "(errors / requests) * 100"
    label       = "4XX Error Rate %"
    return_data = true
  }

  metric_query {
    id = "errors"
    metric {
      metric_name = "4XXError"
      namespace   = "AWS/ApiGateway"
      period      = var.alarm_period
      stat        = "Sum"
      dimensions = {
        ApiName = each.value
      }
    }
  }

  metric_query {
    id = "requests"
    metric {
      metric_name = "Count"
      namespace   = "AWS/ApiGateway"
      period      = var.alarm_period
      stat        = "Sum"
      dimensions = {
        ApiName = each.value
      }
    }
  }

  alarm_actions = var.alarm_actions
  ok_actions    = var.enable_ok_actions ? var.alarm_actions : []

  tags = merge(local.common_tags, {
    Name      = "${each.value}-4xx-high"
    ApiPrefix = each.value
  })
}

################################################################################
# Latency Alarm (p99)
################################################################################

resource "aws_cloudwatch_metric_alarm" "api_latency" {
  for_each = var.api_names

  alarm_name          = "${each.value}-latency-high"
  alarm_description   = "API Gateway ${each.value} p99 latency exceeds ${var.alarm_latency_threshold_ms}ms"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "Latency"
  namespace           = "AWS/ApiGateway"
  period              = var.alarm_period
  extended_statistic  = "p99"
  threshold           = var.alarm_latency_threshold_ms
  treat_missing_data  = "notBreaching"

  dimensions = {
    ApiName = each.value
  }

  alarm_actions = var.alarm_actions
  ok_actions    = var.enable_ok_actions ? var.alarm_actions : []

  tags = merge(local.common_tags, {
    Name      = "${each.value}-latency-high"
    ApiPrefix = each.value
  })
}

################################################################################
# Integration Latency Alarm (p99)
################################################################################

resource "aws_cloudwatch_metric_alarm" "api_integration_latency" {
  for_each = var.api_names

  alarm_name          = "${each.value}-integration-latency-high"
  alarm_description   = "API Gateway ${each.value} p99 integration latency exceeds ${var.alarm_integration_latency_threshold_ms}ms"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "IntegrationLatency"
  namespace           = "AWS/ApiGateway"
  period              = var.alarm_period
  extended_statistic  = "p99"
  threshold           = var.alarm_integration_latency_threshold_ms
  treat_missing_data  = "notBreaching"

  dimensions = {
    ApiName = each.value
  }

  alarm_actions = var.alarm_actions
  ok_actions    = var.enable_ok_actions ? var.alarm_actions : []

  tags = merge(local.common_tags, {
    Name      = "${each.value}-integration-latency-high"
    ApiPrefix = each.value
  })
}
