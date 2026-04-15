################################################################################
# WAF Alarms Module Outputs
################################################################################

output "alarm_blocked_spike_arn" {
  description = "ARN of the blocked requests spike alarm"
  value       = aws_cloudwatch_metric_alarm.waf_blocked_spike.arn
}

output "alarm_rate_limited_arn" {
  description = "ARN of the rate-limit triggered alarm (if created)"
  value       = try(aws_cloudwatch_metric_alarm.waf_rate_limited[0].arn, null)
}

output "alarm_sqli_detected_arn" {
  description = "ARN of the SQL injection detection alarm (if created)"
  value       = try(aws_cloudwatch_metric_alarm.waf_sqli_detected[0].arn, null)
}
