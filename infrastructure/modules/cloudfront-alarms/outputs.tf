################################################################################
# CloudFront Alarms Module Outputs
################################################################################

output "alarm_5xx_arn" {
  description = "ARN of the CloudFront 5XX error rate alarm"
  value       = aws_cloudwatch_metric_alarm.cloudfront_5xx.arn
}

output "alarm_4xx_arn" {
  description = "ARN of the CloudFront 4XX error rate alarm"
  value       = aws_cloudwatch_metric_alarm.cloudfront_4xx.arn
}

output "alarm_origin_latency_arn" {
  description = "ARN of the origin latency alarm (if created)"
  value       = try(aws_cloudwatch_metric_alarm.cloudfront_origin_latency[0].arn, null)
}
