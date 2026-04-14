################################################################################
# Network Alarms Module Outputs
################################################################################

output "alarm_nat_port_allocation_arns" {
  description = "Map of NAT Gateway name to port allocation error alarm ARN"
  value       = { for k, v in aws_cloudwatch_metric_alarm.nat_port_allocation_errors : k => v.arn }
}

output "alarm_nat_packets_drop_arns" {
  description = "Map of NAT Gateway name to packets drop alarm ARN"
  value       = { for k, v in aws_cloudwatch_metric_alarm.nat_packets_drop : k => v.arn }
}

output "alarm_firewall_dropped_arn" {
  description = "ARN of the Network Firewall dropped packets alarm (if created)"
  value       = try(aws_cloudwatch_metric_alarm.firewall_dropped_packets[0].arn, null)
}
