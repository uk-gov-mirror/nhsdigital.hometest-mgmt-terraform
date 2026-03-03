output "lambda_function_name" {
  description = "Name of the test Lambda function"
  value       = module.db_auth_test_lambda.lambda_function_name
}

output "lambda_function_arn" {
  description = "ARN of the test Lambda function"
  value       = module.db_auth_test_lambda.lambda_function_arn
}
