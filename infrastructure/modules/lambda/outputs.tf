################################################################################
# Lambda Module Outputs
################################################################################

output "function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.this.function_name
}

output "function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.this.arn
}

output "function_invoke_arn" {
  description = "Invoke ARN of the Lambda function"
  value       = aws_lambda_function.this.invoke_arn
}

output "function_qualified_arn" {
  description = "Qualified ARN of the Lambda function (includes version)"
  value       = aws_lambda_function.this.qualified_arn
}

output "function_version" {
  description = "Latest published version of the Lambda function"
  value       = aws_lambda_function.this.version
}

output "log_group_name" {
  description = "Name of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.lambda.name
}

output "log_group_arn" {
  description = "ARN of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.lambda.arn
}

output "function_url" {
  description = "Lambda function URL (if created)"
  value       = try(aws_lambda_function_url.this[0].function_url, null)
}

output "alias_arn" {
  description = "ARN of the Lambda alias (if created)"
  value       = try(aws_lambda_alias.this[0].arn, null)
}

output "alias_invoke_arn" {
  description = "Invoke ARN of the Lambda alias (if created)"
  value       = try(aws_lambda_alias.this[0].invoke_arn, null)
}

output "error_alarm_arn" {
  description = "ARN of the Lambda errors CloudWatch alarm (if created)"
  value       = try(aws_cloudwatch_metric_alarm.lambda_errors[0].arn, null)
}

output "throttle_alarm_arn" {
  description = "ARN of the Lambda throttles CloudWatch alarm (if created)"
  value       = try(aws_cloudwatch_metric_alarm.lambda_throttles[0].arn, null)
}

output "duration_alarm_arn" {
  description = "ARN of the Lambda duration CloudWatch alarm (if created)"
  value       = try(aws_cloudwatch_metric_alarm.lambda_duration[0].arn, null)
}

output "concurrency_alarm_arn" {
  description = "ARN of the Lambda concurrency CloudWatch alarm (if created)"
  value       = try(aws_cloudwatch_metric_alarm.lambda_concurrent_executions[0].arn, null)
}

output "logged_errors_alarm_arn" {
  description = "ARN of the Lambda logged errors CloudWatch alarm (if created)"
  value       = try(aws_cloudwatch_metric_alarm.lambda_logged_errors[0].arn, null)
}
