################################################################################
# WAF Alarms Module
# CloudWatch alarms for WAFv2 Web ACL metrics
################################################################################

locals {
  resource_prefix = "${var.project_name}-${var.aws_account_shortname}-${var.environment}"

  common_tags = merge(
    var.tags,
    {
      Service      = "waf-alarms"
      ManagedBy    = "terraform"
      Module       = "waf-alarms"
      ResourceType = "cloudwatch-alarm"
    }
  )
}

################################################################################
# WAF Blocked Requests Spike Alarm
################################################################################

resource "aws_cloudwatch_metric_alarm" "waf_blocked_spike" {
  alarm_name          = "${local.resource_prefix}-${var.waf_name_suffix}-blocked-spike"
  alarm_description   = "WAF ${var.waf_name_suffix} blocked requests exceed ${var.alarm_blocked_threshold} per period"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "BlockedRequests"
  namespace           = "AWS/WAFV2"
  period              = var.alarm_period
  statistic           = "Sum"
  threshold           = var.alarm_blocked_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    WebACL = var.web_acl_name
    Region = var.aws_region
    Rule   = "ALL"
  }

  alarm_actions = var.alarm_actions
  ok_actions    = var.enable_ok_actions ? var.alarm_actions : []

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-${var.waf_name_suffix}-blocked-spike"
  })
}

################################################################################
# WAF Rate Limit Triggered Alarm
################################################################################

resource "aws_cloudwatch_metric_alarm" "waf_rate_limited" {
  count = var.rate_limit_metric_name != null ? 1 : 0

  alarm_name          = "${local.resource_prefix}-${var.waf_name_suffix}-rate-limited"
  alarm_description   = "WAF ${var.waf_name_suffix} rate limiting rule triggered"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "BlockedRequests"
  namespace           = "AWS/WAFV2"
  period              = var.alarm_period
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    WebACL = var.web_acl_name
    Region = var.aws_region
    Rule   = var.rate_limit_metric_name
  }

  alarm_actions = var.alarm_actions
  ok_actions    = var.enable_ok_actions ? var.alarm_actions : []

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-${var.waf_name_suffix}-rate-limited"
  })
}

################################################################################
# WAF SQL Injection Detected Alarm
################################################################################

resource "aws_cloudwatch_metric_alarm" "waf_sqli_detected" {
  count = var.sqli_metric_name != null ? 1 : 0

  alarm_name          = "${local.resource_prefix}-${var.waf_name_suffix}-sqli-detected"
  alarm_description   = "WAF ${var.waf_name_suffix} SQL injection attack detected and blocked"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "BlockedRequests"
  namespace           = "AWS/WAFV2"
  period              = var.alarm_period
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    WebACL = var.web_acl_name
    Region = var.aws_region
    Rule   = var.sqli_metric_name
  }

  alarm_actions = var.alarm_actions
  ok_actions    = var.enable_ok_actions ? var.alarm_actions : []

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-${var.waf_name_suffix}-sqli-detected"
  })
}
