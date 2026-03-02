# HomeTest Service Application Infrastructure

This directory contains Terraform/Terragrunt configuration for deploying the HomeTest Service application infrastructure.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              CloudFront                                      │
│                         (SPA Distribution)                                   │
│                    ┌──────────────────────────────┐                         │
│                    │  Security Headers Policy      │                         │
│                    │  - CSP, X-Frame-Options       │                         │
│                    │  - HSTS, XSS Protection       │                         │
│                    └──────────────────────────────┘                         │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                    ┌───────────────┴───────────────┐
                    ▼                               ▼
        ┌───────────────────┐           ┌───────────────────┐
        │   S3 Bucket       │           │   API Gateway     │
        │  (SPA Assets)     │           │   (REST API)      │
        │  - OAC Access     │           │  - X-Ray Tracing  │
        │  - Versioning     │           │  - WAF Integration│
        │  - Encryption     │           │  - Access Logging │
        └───────────────────┘           └───────────────────┘
                                                │
                    ┌───────────────────────────┼───────────────────────────┐
                    ▼                           ▼                           ▼
        ┌───────────────────┐       ┌───────────────────┐       ┌───────────────────┐
        │ Lambda Function   │       │ Lambda Function   │       │ Lambda Function   │
        │ eligibility-test  │       │ order-router      │       │ hello-world       │
        │ - X-Ray Tracing   │       │ - X-Ray Tracing   │       │ - X-Ray Tracing   │
        │ - KMS Encryption  │       │ - KMS Encryption  │       │ - KMS Encryption  │
        └───────────────────┘       └───────────────────┘       └───────────────────┘
```

## Security Features

### Lambda Functions
- ✅ X-Ray tracing enabled for distributed tracing
- ✅ KMS encryption for environment variables
- ✅ CloudWatch logs with encryption
- ✅ Least privilege IAM execution role
- ✅ VPC support for private resource access
- ✅ Dead letter queue support

### API Gateway
- ✅ CloudWatch access logging with structured JSON
- ✅ X-Ray tracing enabled
- ✅ WAF Web ACL integration
- ✅ Throttling configuration
- ✅ TLS 1.2 minimum for custom domains
- ✅ Regional endpoint with optional custom domain

### CloudFront SPA
- ✅ Origin Access Control (OAC) for S3
- ✅ Security headers (CSP, HSTS, X-Frame-Options, etc.)
- ✅ TLS 1.2 minimum protocol version
- ✅ HTTP/2 and HTTP/3 support
- ✅ SPA routing with CloudFront Functions
- ✅ Geo-restriction support
- ✅ WAF integration

### Developer Deployment Role
- ✅ MFA requirement
- ✅ IP-based restrictions (optional)
- ✅ External ID support (confused deputy protection)
- ✅ Explicit deny for dangerous actions
- ✅ Scoped to specific resources

## Prerequisites

1. AWS Account with appropriate permissions
2. Terraform >= 1.5.0
3. Terragrunt >= 0.50.0
4. AWS CLI configured

## Deployment

### Infrastructure Deployment (via Terragrunt)

```bash
# Navigate to the environment directory
cd infrastructure/environments/poc/dev/hometest-app

# Initialize and plan
terragrunt init
terragrunt plan

# Apply the infrastructure
terragrunt apply
```

### Lambda Deployment (for Developers)

1. Configure AWS CLI with the developer deployment role:

```bash
# Add to ~/.aws/config
[profile nhs-hometest-dev-deploy]
role_arn = arn:aws:iam::ACCOUNT_ID:role/nhs-hometest-dev-developer-deploy
source_profile = default
mfa_serial = arn:aws:iam::YOUR_ACCOUNT_ID:mfa/YOUR_USERNAME
```

2. Build and deploy Lambda:

```bash
# Build Lambda
cd hometest-service/lambdas
npm run build

# Upload to S3
aws s3 cp dist/eligibility-test-info-lambda.zip \
  s3://nhs-hometest-dev-artifacts-ACCOUNT_ID/lambdas/ \
  --profile nhs-hometest-dev-deploy

# Update Lambda function
aws lambda update-function-code \
  --function-name nhs-hometest-dev-eligibility-test-info \
  --s3-bucket nhs-hometest-dev-artifacts-ACCOUNT_ID \
  --s3-key lambdas/eligibility-test-info-lambda.zip \
  --profile nhs-hometest-dev-deploy
```

### SPA Deployment (for Developers)

```bash
# Build SPA
cd hometest-service/ui
npm run build

# Deploy to S3
aws s3 sync out/ s3://nhs-hometest-dev-spa-ACCOUNT_ID \
  --delete \
  --profile nhs-hometest-dev-deploy

# Invalidate CloudFront cache
aws cloudfront create-invalidation \
  --distribution-id DISTRIBUTION_ID \
  --paths "/*" \
  --profile nhs-hometest-dev-deploy
```

## Modules

| Module | Description |
|--------|-------------|
| `lambda` | Lambda function with security best practices |
| `lambda-iam` | Lambda execution IAM role with least privilege |
| `api-gateway` | REST API Gateway with logging and security |
| `cloudfront-spa` | CloudFront distribution for SPA with S3 origin |
| `deployment-artifacts` | S3 bucket for Lambda deployment packages |
| `developer-iam` | IAM role for developers to deploy applications |

## Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `project_name` | Project name prefix | `nhs-hometest` |
| `environment` | Environment name | Required |
| `lambda_runtime` | Lambda runtime | `nodejs20.x` |
| `lambda_timeout` | Lambda timeout (seconds) | `30` |
| `lambda_memory_size` | Lambda memory (MB) | `256` |
| `log_retention_days` | CloudWatch log retention | `30` |
| `developer_account_arns` | Developer IAM ARNs | Required |
| `developer_require_mfa` | Require MFA | `true` |

### Custom Domains

To use custom domains, set the following variables:

```hcl
# API Gateway custom domain
api_custom_domain_name  = "api.example.com"
api_acm_certificate_arn = "arn:aws:acm:eu-west-2:ACCOUNT:certificate/XXX"

# CloudFront custom domain (certificate must be in us-east-1)
spa_custom_domain_names = ["app.example.com"]
spa_acm_certificate_arn = "arn:aws:acm:us-east-1:ACCOUNT:certificate/XXX"
route53_zone_id         = "Z1234567890"
```

## Outputs

After deployment, you'll have access to:

- `api_gateway_invoke_url` - API Gateway endpoint URL
- `cloudfront_url` - CloudFront distribution URL
- `developer_role_arn` - Developer deployment role ARN
- `deploy_lambda_command` - Commands to deploy Lambda
- `deploy_spa_command` - Commands to deploy SPA

## Troubleshooting

### Lambda deployment fails
- Ensure you have assumed the developer role with MFA
- Check S3 bucket permissions
- Verify Lambda function name matches

### CloudFront returns 403
- Check S3 bucket policy allows CloudFront OAC
- Verify index.html exists in S3
- Check CloudFront distribution is deployed

### API Gateway returns 500
- Check Lambda execution role permissions
- Review CloudWatch logs for Lambda errors
- Ensure environment variables are set correctly

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.14.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.33.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | ~> 6.33.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_cloudfront_spa"></a> [cloudfront\_spa](#module\_cloudfront\_spa) | ../../modules/cloudfront-spa | n/a |
| <a name="module_lambda_iam"></a> [lambda\_iam](#module\_lambda\_iam) | ../../modules/lambda-iam | n/a |
| <a name="module_lambdas"></a> [lambdas](#module\_lambdas) | ../../modules/lambda | n/a |
| <a name="module_sqs_events"></a> [sqs\_events](#module\_sqs\_events) | ../../modules/sqs | n/a |
| <a name="module_sqs_notifications"></a> [sqs\_notifications](#module\_sqs\_notifications) | ../../modules/sqs | n/a |
| <a name="module_sqs_order_placement"></a> [sqs\_order\_placement](#module\_sqs\_order\_placement) | ../../modules/sqs | n/a |
| <a name="module_sqs_order_results"></a> [sqs\_order\_results](#module\_sqs\_order\_results) | ../../modules/sqs | n/a |

## Resources

| Name | Type |
|------|------|
| [aws_api_gateway_account.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/api_gateway_account) | resource |
| [aws_api_gateway_authorizer.cognito_supplier](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/api_gateway_authorizer) | resource |
| [aws_api_gateway_deployment.apis](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/api_gateway_deployment) | resource |
| [aws_api_gateway_integration.options](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/api_gateway_integration) | resource |
| [aws_api_gateway_integration.proxy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/api_gateway_integration) | resource |
| [aws_api_gateway_integration.root](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/api_gateway_integration) | resource |
| [aws_api_gateway_integration_response.options](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/api_gateway_integration_response) | resource |
| [aws_api_gateway_method.options](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/api_gateway_method) | resource |
| [aws_api_gateway_method.proxy_any](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/api_gateway_method) | resource |
| [aws_api_gateway_method.root](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/api_gateway_method) | resource |
| [aws_api_gateway_method_response.options](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/api_gateway_method_response) | resource |
| [aws_api_gateway_method_settings.apis](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/api_gateway_method_settings) | resource |
| [aws_api_gateway_resource.proxy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/api_gateway_resource) | resource |
| [aws_api_gateway_rest_api.apis](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/api_gateway_rest_api) | resource |
| [aws_api_gateway_stage.apis](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/api_gateway_stage) | resource |
| [aws_cloudwatch_log_group.api_gateway](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_iam_role.api_gateway_cloudwatch](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.api_gateway_cloudwatch](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_lambda_event_source_mapping.order_router_order_placement](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_event_source_mapping) | resource |
| [aws_lambda_event_source_mapping.sqs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_event_source_mapping) | resource |
| [aws_lambda_permission.api_gateway](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_permission) | resource |
| [aws_resourcegroups_group.rg](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/resourcegroups_group) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_acm_certificate_arn"></a> [acm\_certificate\_arn](#input\_acm\_certificate\_arn) | ACM certificate ARN for CloudFront (us-east-1, from shared\_services) | `string` | `null` | no |
| <a name="input_api_endpoint_type"></a> [api\_endpoint\_type](#input\_api\_endpoint\_type) | API Gateway endpoint type | `string` | `"REGIONAL"` | no |
| <a name="input_api_stage_name"></a> [api\_stage\_name](#input\_api\_stage\_name) | API Gateway stage name | `string` | `"v1"` | no |
| <a name="input_api_throttling_burst_limit"></a> [api\_throttling\_burst\_limit](#input\_api\_throttling\_burst\_limit) | API Gateway throttling burst limit | `number` | `1000` | no |
| <a name="input_api_throttling_rate_limit"></a> [api\_throttling\_rate\_limit](#input\_api\_throttling\_rate\_limit) | API Gateway throttling rate limit | `number` | `2000` | no |
| <a name="input_authorized_api_prefixes"></a> [authorized\_api\_prefixes](#input\_authorized\_api\_prefixes) | Set of API prefixes that require Cognito authorization | `set(string)` | `[]` | no |
| <a name="input_aws_account_id"></a> [aws\_account\_id](#input\_aws\_account\_id) | AWS account ID for resources | `string` | n/a | yes |
| <a name="input_aws_account_shortname"></a> [aws\_account\_shortname](#input\_aws\_account\_shortname) | AWS account short name/alias for resource naming | `string` | n/a | yes |
| <a name="input_aws_allowed_regions"></a> [aws\_allowed\_regions](#input\_aws\_allowed\_regions) | List of AWS regions allowed for resource deployment | `list(string)` | <pre>[<br/>  "eu-west-2",<br/>  "us-east-1"<br/>]</pre> | no |
| <a name="input_aws_region"></a> [aws\_region](#input\_aws\_region) | AWS region for resources | `string` | n/a | yes |
| <a name="input_cloudfront_logging_bucket_domain_name"></a> [cloudfront\_logging\_bucket\_domain\_name](#input\_cloudfront\_logging\_bucket\_domain\_name) | S3 bucket domain name for CloudFront access logs | `string` | `null` | no |
| <a name="input_cloudfront_price_class"></a> [cloudfront\_price\_class](#input\_cloudfront\_price\_class) | CloudFront price class | `string` | `"PriceClass_100"` | no |
| <a name="input_cognito_user_pool_arn"></a> [cognito\_user\_pool\_arn](#input\_cognito\_user\_pool\_arn) | ARN of the Cognito User Pool | `string` | n/a | yes |
| <a name="input_content_security_policy"></a> [content\_security\_policy](#input\_content\_security\_policy) | Content Security Policy header | `string` | `"default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; font-src 'self' data:; connect-src 'self' https:; frame-ancestors 'none';"` | no |
| <a name="input_custom_domain_name"></a> [custom\_domain\_name](#input\_custom\_domain\_name) | Custom domain name for the environment (e.g., dev1.hometest.service.nhs.uk) | `string` | `null` | no |
| <a name="input_enable_cloudfront_logging"></a> [enable\_cloudfront\_logging](#input\_enable\_cloudfront\_logging) | Enable CloudFront access logging | `bool` | `false` | no |
| <a name="input_enable_vpc_access"></a> [enable\_vpc\_access](#input\_enable\_vpc\_access) | Enable VPC access for Lambda functions | `bool` | `false` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment name (dev, dev1, dev2, staging, prod) | `string` | n/a | yes |
| <a name="input_geo_restriction_locations"></a> [geo\_restriction\_locations](#input\_geo\_restriction\_locations) | List of country codes for geo restriction | `list(string)` | `[]` | no |
| <a name="input_geo_restriction_type"></a> [geo\_restriction\_type](#input\_geo\_restriction\_type) | Geo restriction type (whitelist, blacklist, none) | `string` | `"none"` | no |
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | ARN of shared KMS key (from shared\_services) | `string` | n/a | yes |
| <a name="input_lambda_additional_kms_key_arns"></a> [lambda\_additional\_kms\_key\_arns](#input\_lambda\_additional\_kms\_key\_arns) | Additional KMS key ARNs for Lambda to decrypt secrets (e.g., secrets encrypted with different keys) | `list(string)` | `[]` | no |
| <a name="input_lambda_architecture"></a> [lambda\_architecture](#input\_lambda\_architecture) | Instruction set architecture for Lambda functions (x86\_64 or arm64) | `string` | `"arm64"` | no |
| <a name="input_lambda_aurora_cluster_resource_ids"></a> [lambda\_aurora\_cluster\_resource\_ids](#input\_lambda\_aurora\_cluster\_resource\_ids) | Aurora cluster resource IDs to grant Lambda IAM database authentication (rds-db:connect) | `list(string)` | `[]` | no |
| <a name="input_lambda_dynamodb_table_arns"></a> [lambda\_dynamodb\_table\_arns](#input\_lambda\_dynamodb\_table\_arns) | DynamoDB table ARNs for Lambda access | `list(string)` | `[]` | no |
| <a name="input_lambda_memory_size"></a> [lambda\_memory\_size](#input\_lambda\_memory\_size) | Lambda memory size in MB | `number` | `256` | no |
| <a name="input_lambda_runtime"></a> [lambda\_runtime](#input\_lambda\_runtime) | Lambda runtime | `string` | `"nodejs20.x"` | no |
| <a name="input_lambda_s3_bucket_arns"></a> [lambda\_s3\_bucket\_arns](#input\_lambda\_s3\_bucket\_arns) | Additional S3 bucket ARNs for Lambda access | `list(string)` | `[]` | no |
| <a name="input_lambda_secrets_arns"></a> [lambda\_secrets\_arns](#input\_lambda\_secrets\_arns) | Secrets Manager ARNs for Lambda access | `list(string)` | `[]` | no |
| <a name="input_lambda_security_group_ids"></a> [lambda\_security\_group\_ids](#input\_lambda\_security\_group\_ids) | Security group IDs for Lambda (from network) | `list(string)` | `[]` | no |
| <a name="input_lambda_sqs_queue_arns"></a> [lambda\_sqs\_queue\_arns](#input\_lambda\_sqs\_queue\_arns) | SQS queue ARNs for Lambda access | `list(string)` | `[]` | no |
| <a name="input_lambda_ssm_parameter_arns"></a> [lambda\_ssm\_parameter\_arns](#input\_lambda\_ssm\_parameter\_arns) | SSM parameter ARNs for Lambda access | `list(string)` | `[]` | no |
| <a name="input_lambda_subnet_ids"></a> [lambda\_subnet\_ids](#input\_lambda\_subnet\_ids) | Private subnet IDs for Lambda VPC configuration (from network) | `list(string)` | `[]` | no |
| <a name="input_lambda_timeout"></a> [lambda\_timeout](#input\_lambda\_timeout) | Lambda timeout in seconds | `number` | `30` | no |
| <a name="input_lambdas"></a> [lambdas](#input\_lambdas) | Map of Lambda function configurations. Each key is the lambda name. | <pre>map(object({<br/>    description                    = optional(string, "Lambda function")<br/>    handler                        = optional(string, "index.handler")<br/>    runtime                        = optional(string, null) # null = use var.lambda_runtime<br/>    timeout                        = optional(number, null) # null = use var.lambda_timeout<br/>    memory_size                    = optional(number, null) # null = use var.lambda_memory_size<br/>    zip_path                       = optional(string, null) # Local path to zip file (Terraform uploads directly)<br/>    s3_key                         = optional(string, null) # S3 key if already uploaded<br/>    source_hash                    = optional(string, null) # Source code hash for updates<br/>    environment                    = optional(map(string), {})<br/>    api_path_prefix                = optional(string, null) # API Gateway path prefix (e.g., "api1" -> /api1/*)<br/>    sqs_trigger                    = optional(bool, false)  # Enable SQS event source mapping<br/>    secrets_arn                    = optional(string, null) # Secrets Manager ARN for this lambda<br/>    reserved_concurrent_executions = optional(number, -1)<br/><br/>    authorization        = optional(string, "NONE")   # "NONE" or "COGNITO_USER_POOLS"<br/>    authorization_scopes = optional(list(string), []) # e.g., ["results/write", "orders/read"]<br/>  }))</pre> | `{}` | no |
| <a name="input_lambdas_base_path"></a> [lambdas\_base\_path](#input\_lambdas\_base\_path) | Base path where lambda zip files are located | `string` | `"../../../examples/lambdas"` | no |
| <a name="input_log_retention_days"></a> [log\_retention\_days](#input\_log\_retention\_days) | CloudWatch log retention in days | `number` | `14` | no |
| <a name="input_permissions_policy"></a> [permissions\_policy](#input\_permissions\_policy) | Permissions Policy header | `string` | `"accelerometer=(), camera=(), geolocation=(), gyroscope=(), magnetometer=(), microphone=(), payment=(), usb=()"` | no |
| <a name="input_project_name"></a> [project\_name](#input\_project\_name) | Name of the project | `string` | n/a | yes |
| <a name="input_route53_zone_id"></a> [route53\_zone\_id](#input\_route53\_zone\_id) | Route53 hosted zone ID (from network) | `string` | n/a | yes |
| <a name="input_sns_alerts_topic_arn"></a> [sns\_alerts\_topic\_arn](#input\_sns\_alerts\_topic\_arn) | ARN of shared alerts SNS topic (from shared\_services) | `string` | `null` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to all resources | `map(string)` | `{}` | no |
| <a name="input_use_placeholder_lambda"></a> [use\_placeholder\_lambda](#input\_use\_placeholder\_lambda) | Use placeholder Lambda code for initial deployment (when S3 code doesn't exist yet) | `bool` | `false` | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC ID (from network) | `string` | `null` | no |
| <a name="input_waf_cloudfront_arn"></a> [waf\_cloudfront\_arn](#input\_waf\_cloudfront\_arn) | ARN of CloudFront WAF Web ACL (from shared\_services) | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_api1_gateway_id"></a> [api1\_gateway\_id](#output\_api1\_gateway\_id) | ID of API Gateway 1 (legacy - use api\_gateways instead) |
| <a name="output_api1_lambda_arn"></a> [api1\_lambda\_arn](#output\_api1\_lambda\_arn) | ARN of the API 1 Lambda (legacy - use lambda\_functions instead) |
| <a name="output_api1_lambda_name"></a> [api1\_lambda\_name](#output\_api1\_lambda\_name) | Name of the API 1 Lambda (legacy - use lambda\_functions instead) |
| <a name="output_api2_gateway_id"></a> [api2\_gateway\_id](#output\_api2\_gateway\_id) | ID of API Gateway 2 (legacy - use api\_gateways instead) |
| <a name="output_api2_lambda_arn"></a> [api2\_lambda\_arn](#output\_api2\_lambda\_arn) | ARN of the API 2 Lambda (legacy - use lambda\_functions instead) |
| <a name="output_api2_lambda_name"></a> [api2\_lambda\_name](#output\_api2\_lambda\_name) | Name of the API 2 Lambda (legacy - use lambda\_functions instead) |
| <a name="output_api_gateways"></a> [api\_gateways](#output\_api\_gateways) | Map of all API Gateway details |
| <a name="output_cloudfront_distribution_arn"></a> [cloudfront\_distribution\_arn](#output\_cloudfront\_distribution\_arn) | CloudFront distribution ARN |
| <a name="output_cloudfront_distribution_id"></a> [cloudfront\_distribution\_id](#output\_cloudfront\_distribution\_id) | CloudFront distribution ID |
| <a name="output_cloudfront_domain_name"></a> [cloudfront\_domain\_name](#output\_cloudfront\_domain\_name) | CloudFront distribution domain name |
| <a name="output_deployment_info"></a> [deployment\_info](#output\_deployment\_info) | Information for CI/CD deployments |
| <a name="output_environment_urls"></a> [environment\_urls](#output\_environment\_urls) | All environment URLs |
| <a name="output_lambda_execution_role_arn"></a> [lambda\_execution\_role\_arn](#output\_lambda\_execution\_role\_arn) | ARN of the Lambda execution role |
| <a name="output_lambda_functions"></a> [lambda\_functions](#output\_lambda\_functions) | Map of all Lambda function details |
| <a name="output_lambda_functions_detail"></a> [lambda\_functions\_detail](#output\_lambda\_functions\_detail) | Map of Lambda function details |
| <a name="output_login_endpoint"></a> [login\_endpoint](#output\_login\_endpoint) | Login Lambda endpoint URL |
| <a name="output_notifications_dlq_arn"></a> [notifications\_dlq\_arn](#output\_notifications\_dlq\_arn) | ARN of the notifications dead letter queue |
| <a name="output_notifications_dlq_url"></a> [notifications\_dlq\_url](#output\_notifications\_dlq\_url) | URL of the notifications dead letter queue |
| <a name="output_notifications_queue_arn"></a> [notifications\_queue\_arn](#output\_notifications\_queue\_arn) | ARN of the notifications SQS queue (FIFO) |
| <a name="output_notifications_queue_url"></a> [notifications\_queue\_url](#output\_notifications\_queue\_url) | URL of the notifications SQS queue (FIFO) |
| <a name="output_order_placement_queue_arn"></a> [order\_placement\_queue\_arn](#output\_order\_placement\_queue\_arn) | ARN of the order placement SQS queue |
| <a name="output_order_placement_queue_url"></a> [order\_placement\_queue\_url](#output\_order\_placement\_queue\_url) | URL of the order placement SQS queue |
| <a name="output_order_results_queue_arn"></a> [order\_results\_queue\_arn](#output\_order\_results\_queue\_arn) | ARN of the order results SQS queue |
| <a name="output_order_results_queue_url"></a> [order\_results\_queue\_url](#output\_order\_results\_queue\_url) | URL of the order results SQS queue |
| <a name="output_spa_bucket_arn"></a> [spa\_bucket\_arn](#output\_spa\_bucket\_arn) | S3 bucket ARN for SPA static assets |
| <a name="output_spa_bucket_id"></a> [spa\_bucket\_id](#output\_spa\_bucket\_id) | S3 bucket ID for SPA static assets |
| <a name="output_spa_url"></a> [spa\_url](#output\_spa\_url) | Full URL for SPA |
| <a name="output_sqs_dlq_arn"></a> [sqs\_dlq\_arn](#output\_sqs\_dlq\_arn) | ARN of the events dead letter queue |
| <a name="output_sqs_dlq_url"></a> [sqs\_dlq\_url](#output\_sqs\_dlq\_url) | URL of the events dead letter queue |
| <a name="output_sqs_queue_arn"></a> [sqs\_queue\_arn](#output\_sqs\_queue\_arn) | ARN of the events SQS queue |
| <a name="output_sqs_queue_url"></a> [sqs\_queue\_url](#output\_sqs\_queue\_url) | URL of the events SQS queue |
<!-- END_TF_DOCS -->
