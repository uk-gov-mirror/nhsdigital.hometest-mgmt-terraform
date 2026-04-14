################################################################################
# Slack Alerts Module Outputs
################################################################################

output "lambda_function_arn" {
  description = "ARN of the Slack notifier Lambda function"
  value       = aws_lambda_function.notifier.arn
}

output "lambda_function_name" {
  description = "Name of the Slack notifier Lambda function"
  value       = aws_lambda_function.notifier.function_name
}

output "lambda_role_arn" {
  description = "ARN of the IAM role used by the Slack notifier Lambda"
  value       = aws_iam_role.notifier.arn
}
