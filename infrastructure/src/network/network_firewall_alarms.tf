################################################################################
# Network Firewall CloudWatch Alarms
#
# Monitors firewall health and traffic anomalies.
# Alarms notify via SNS if firewall_alert_sns_topic_arn is set.
################################################################################

locals {
  firewall_alarm_actions = var.firewall_alert_sns_topic_arn != "" ? [var.firewall_alert_sns_topic_arn] : []
}

# --------------------------------------------------------------------------
# Dropped Packets — High Rate (possible misconfiguration or attack)
# --------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "firewall_dropped_packets_high" {
  count = var.enable_network_firewall ? 1 : 0

  alarm_name          = "${local.resource_prefix}-firewall-dropped-packets-high"
  alarm_description   = "Network Firewall dropped packets exceeded threshold — possible misconfiguration blocking legitimate traffic or active attack."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "DroppedPackets"
  namespace           = "AWS/NetworkFirewall"
  period              = 300
  statistic           = "Sum"
  threshold           = 1000
  treat_missing_data  = "notBreaching"

  dimensions = {
    FirewallName = aws_networkfirewall_firewall.main[0].name
  }

  alarm_actions = local.firewall_alarm_actions
  ok_actions    = local.firewall_alarm_actions

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-firewall-dropped-packets-high"
  })
}

# --------------------------------------------------------------------------
# Passed Packets — Drop to Zero (firewall may be blocking all traffic)
# --------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "firewall_passed_packets_zero" {
  count = var.enable_network_firewall ? 1 : 0

  alarm_name          = "${local.resource_prefix}-firewall-passed-packets-zero"
  alarm_description   = "Network Firewall passed zero packets — firewall may be blocking all traffic, causing an outage."
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = 3
  metric_name         = "PassedPackets"
  namespace           = "AWS/NetworkFirewall"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "breaching"

  dimensions = {
    FirewallName = aws_networkfirewall_firewall.main[0].name
  }

  alarm_actions = local.firewall_alarm_actions
  ok_actions    = local.firewall_alarm_actions

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-firewall-passed-packets-zero"
  })
}

# --------------------------------------------------------------------------
# Received Packets — Drop to Zero (firewall endpoint may be unhealthy)
# --------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "firewall_received_packets_zero" {
  count = var.enable_network_firewall ? 1 : 0

  alarm_name          = "${local.resource_prefix}-firewall-received-packets-zero"
  alarm_description   = "Network Firewall received zero packets — firewall endpoint may be unhealthy or routing is broken."
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = 3
  metric_name         = "ReceivedPackets"
  namespace           = "AWS/NetworkFirewall"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "breaching"

  dimensions = {
    FirewallName = aws_networkfirewall_firewall.main[0].name
  }

  alarm_actions = local.firewall_alarm_actions
  ok_actions    = local.firewall_alarm_actions

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-firewall-received-packets-zero"
  })
}
