################################################################################
# Lambda Module Outputs
################################################################################

output "function_name" {
  description = "Name of the Lambda function"
  value       = module.lambda.lambda_function_name
}

output "function_arn" {
  description = "ARN of the Lambda function"
  value       = module.lambda.lambda_function_arn
}

output "function_invoke_arn" {
  description = "Invoke ARN of the Lambda function"
  value       = module.lambda.lambda_function_invoke_arn
}

output "function_qualified_arn" {
  description = "Qualified ARN of the Lambda function (includes version)"
  value       = module.lambda.lambda_function_qualified_arn
}

output "function_version" {
  description = "Latest published version of the Lambda function"
  value       = module.lambda.lambda_function_version
}

output "log_group_name" {
  description = "Name of the CloudWatch log group"
  value       = module.lambda.lambda_cloudwatch_log_group_name
}

output "log_group_arn" {
  description = "ARN of the CloudWatch log group"
  value       = module.lambda.lambda_cloudwatch_log_group_arn
}

output "role_arn" {
  description = "ARN of the per-Lambda execution IAM role"
  value       = aws_iam_role.this.arn
}

output "role_name" {
  description = "Name of the per-Lambda execution IAM role"
  value       = aws_iam_role.this.name
}

output "error_alarm_arn" {
  description = "ARN of the Lambda errors CloudWatch alarm (if created)"
  value       = try(aws_cloudwatch_metric_alarm.lambda_errors[0].arn, null)
}
