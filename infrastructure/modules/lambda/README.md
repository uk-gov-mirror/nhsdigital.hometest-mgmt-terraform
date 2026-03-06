# Lambda Module

Terraform module for deploying AWS Lambda functions with **per-function least-privilege IAM roles** using the official [terraform-aws-modules/lambda/aws](https://registry.terraform.io/modules/terraform-aws-modules/lambda/aws/latest) module.

## Features

- **Per-Lambda IAM Roles**: Each Lambda gets its own dedicated IAM role with only the permissions it needs
- **Least Privilege**: Secrets, SQS queues, S3, DynamoDB, Aurora are granted individually per function
- **Official Module**: Uses `terraform-aws-modules/lambda/aws` v8.7.0 under the hood
- **Security First**: KMS encryption for environment variables and CloudWatch logs
- **Observability**: X-Ray tracing enabled by default
- **Monitoring**: Optional CloudWatch alarm for Lambda errors (failed invocations)
- **VPC Support**: Optional VPC configuration with scoped ENI permissions
- **Dead Letter Queue**: Failed invocations can be sent to SQS/SNS

## Usage

```hcl
module "my_lambda" {
  source = "../../modules/lambda"

  project_name          = "nhs-hometest"
  aws_account_shortname = "poc"
  function_name         = "my-function"
  environment           = "dev"

  # Required for IAM policy ARN construction
  aws_account_id = "123456789012"
  aws_region     = "eu-west-2"

  # Deployment package
  filename         = "path/to/my-function.zip"
  source_code_hash = filebase64sha256("path/to/my-function.zip")

  # Per-lambda IAM permissions (least privilege)
  secrets_arns               = ["arn:aws:secretsmanager:eu-west-2:123456789012:secret:my-secret-*"]
  aurora_cluster_resource_ids = ["cluster-ABC123"]
  sqs_send_queue_arns        = ["arn:aws:sqs:eu-west-2:123456789012:my-queue"]

  # Infrastructure-level permissions
  enable_vpc_access = true
  enable_xray       = true

  environment_variables = {
    API_URL = "https://api.example.com"
  }

  # Optional VPC configuration
  vpc_subnet_ids         = module.vpc.private_subnet_ids
  vpc_security_group_ids = [aws_security_group.lambda.id]

  # Optional encryption
  lambda_kms_key_arn     = aws_kms_key.lambda.arn
  cloudwatch_kms_key_arn = aws_kms_key.cloudwatch.arn

  tags = {
    Owner       = "platform-team"
    Environment = "dev"
  }
}
```

## Per-Lambda IAM

Each Lambda function gets its own IAM role. Specify exactly which resources each Lambda can access:

| Variable | Description |
|---|---|
| `secrets_arns` | Secrets Manager secrets this Lambda can read |
| `ssm_parameter_arns` | SSM parameters this Lambda can read |
| `kms_key_arns` | KMS keys for decryption |
| `s3_bucket_arns` | S3 buckets for read/write |
| `dynamodb_table_arns` | DynamoDB tables |
| `sqs_send_queue_arns` | SQS queues to send messages to |
| `sqs_receive_queue_arns` | SQS queues to receive/delete messages from |
| `aurora_cluster_resource_ids` | Aurora clusters for IAM DB auth |
| `custom_policies` | Custom JSON policy documents |
| `managed_policy_arns` | AWS managed policy ARNs |

## Security Best Practices

1. **Environment Variable Encryption**: Use `lambda_kms_key_arn` to encrypt sensitive environment variables
2. **Log Encryption**: Use `cloudwatch_kms_key_arn` to encrypt CloudWatch logs
3. **VPC Isolation**: Deploy in VPC with private subnets for accessing internal resources
4. **X-Ray Tracing**: Enabled by default for distributed tracing
5. **Dead Letter Queue**: Configure DLQ to capture failed invocations
6. **Least Privilege**: Ensure the Lambda execution role follows least privilege principle

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| project_name | Name of the project | `string` | n/a | yes |
| function_name | Name of the Lambda function | `string` | n/a | yes |
| environment | Environment name | `string` | n/a | yes |
| lambda_role_arn | ARN of the IAM role | `string` | n/a | yes |
| s3_bucket | S3 bucket for deployment package | `string` | n/a | yes |
| s3_key | S3 key for deployment package | `string` | n/a | yes |
| runtime | Lambda runtime | `string` | `"nodejs20.x"` | no |
| timeout | Function timeout (seconds) | `number` | `30` | no |
| memory_size | Function memory (MB) | `number` | `256` | no |
| create_cloudwatch_alarms | Create CloudWatch alarms for Lambda errors | `bool` | `true` | no |
| alarm_actions | ARNs notified when the alarm triggers (e.g., SNS topics) | `list(string)` | `[]` | no |
| alarm_period | Period over which to evaluate the error metric (seconds) | `number` | `300` | no |
| alarm_evaluation_periods | Number of periods over which to evaluate the alarm | `number` | `1` | no |
| alarm_error_threshold | Threshold for Lambda error alarm (errors per period) | `number` | `1` | no |

## Outputs

| Name | Description |
|------|-------------|
| function_name | Name of the Lambda function |
| function_arn | ARN of the Lambda function |
| function_invoke_arn | Invoke ARN for API Gateway integration |
| log_group_name | CloudWatch log group name |
| error_alarm_arn | ARN of the Lambda errors CloudWatch alarm (if created) |
