################################################################################
# API Gateway Alarms Module Outputs
################################################################################

output "alarm_5xx_arns" {
  description = "Map of API name to 5XX alarm ARN"
  value       = { for k, v in aws_cloudwatch_metric_alarm.api_5xx : k => v.arn }
}

output "alarm_4xx_arns" {
  description = "Map of API name to 4XX alarm ARN"
  value       = { for k, v in aws_cloudwatch_metric_alarm.api_4xx : k => v.arn }
}

output "alarm_latency_arns" {
  description = "Map of API name to latency alarm ARN"
  value       = { for k, v in aws_cloudwatch_metric_alarm.api_latency : k => v.arn }
}

output "alarm_integration_latency_arns" {
  description = "Map of API name to integration latency alarm ARN"
  value       = { for k, v in aws_cloudwatch_metric_alarm.api_integration_latency : k => v.arn }
}
