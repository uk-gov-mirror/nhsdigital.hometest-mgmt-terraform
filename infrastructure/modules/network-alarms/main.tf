################################################################################
# Network Alarms Module
# CloudWatch alarms for NAT Gateways and Network Firewall
################################################################################

locals {
  resource_prefix = "${var.project_name}-${var.aws_account_shortname}-${var.environment}"

  common_tags = merge(
    var.tags,
    {
      Service      = "network-alarms"
      ManagedBy    = "terraform"
      Module       = "network-alarms"
      ResourceType = "cloudwatch-alarm"
    }
  )
}

################################################################################
# NAT Gateway - Port Allocation Errors
################################################################################

resource "aws_cloudwatch_metric_alarm" "nat_port_allocation_errors" {
  for_each = var.nat_gateway_ids

  alarm_name          = "${local.resource_prefix}-natgw-${each.key}-port-alloc-errors"
  alarm_description   = "NAT Gateway ${each.key} port allocation errors detected"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "ErrorPortAllocation"
  namespace           = "AWS/NATGateway"
  period              = var.alarm_period
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    NatGatewayId = each.value
  }

  alarm_actions = var.alarm_actions
  ok_actions    = var.enable_ok_actions ? var.alarm_actions : []

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-natgw-${each.key}-port-alloc-errors"
  })
}

################################################################################
# NAT Gateway - Packets Drop Count
################################################################################

resource "aws_cloudwatch_metric_alarm" "nat_packets_drop" {
  for_each = var.nat_gateway_ids

  alarm_name          = "${local.resource_prefix}-natgw-${each.key}-packets-drop"
  alarm_description   = "NAT Gateway ${each.key} dropping packets"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "PacketsDropCount"
  namespace           = "AWS/NATGateway"
  period              = var.alarm_period
  statistic           = "Sum"
  threshold           = var.alarm_nat_packets_drop_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    NatGatewayId = each.value
  }

  alarm_actions = var.alarm_actions
  ok_actions    = var.enable_ok_actions ? var.alarm_actions : []

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-natgw-${each.key}-packets-drop"
  })
}

################################################################################
# Network Firewall - Dropped Packets
################################################################################

resource "aws_cloudwatch_metric_alarm" "firewall_dropped_packets" {
  count = var.firewall_name != null ? 1 : 0

  alarm_name          = "${local.resource_prefix}-nfw-dropped-packets"
  alarm_description   = "Network Firewall dropped packets exceed ${var.alarm_firewall_dropped_threshold} per period"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "DroppedPackets"
  namespace           = "AWS/NetworkFirewall"
  period              = var.alarm_period
  statistic           = "Sum"
  threshold           = var.alarm_firewall_dropped_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    FirewallName = var.firewall_name
    Engine       = "Stateful"
  }

  alarm_actions = var.alarm_actions
  ok_actions    = var.enable_ok_actions ? var.alarm_actions : []

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-nfw-dropped-packets"
  })
}
