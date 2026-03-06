################################################################################
# HomeTest Service Application Variables
################################################################################

#------------------------------------------------------------------------------
# Project Configuration
#------------------------------------------------------------------------------

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID for resources"
  type        = string
}

variable "aws_account_shortname" {
  description = "AWS account short name/alias for resource naming"
  type        = string
}

variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, dev1, dev2, staging, prod)"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

#------------------------------------------------------------------------------
# Dependencies from shared_services
#------------------------------------------------------------------------------

variable "kms_key_arn" {
  description = "ARN of shared KMS key (from shared_services)"
  type        = string
}

variable "sns_alerts_topic_arn" {
  description = "ARN of shared alerts SNS topic (from shared_services)"
  type        = string
  default     = null
}

variable "waf_cloudfront_arn" {
  description = "ARN of CloudFront WAF Web ACL (from shared_services)"
  type        = string
  default     = null
}

variable "waf_regional_arn" {
  description = "ARN of Regional WAF Web ACL to associate with API Gateway stages (from shared_services)"
  type        = string
  default     = null
}

# variable "deployment_bucket_id" {
#   description = "ID of shared deployment artifacts bucket (from shared_services)"
#   type        = string
# }

# variable "deployment_bucket_arn" {
#   description = "ARN of shared deployment artifacts bucket (from shared_services)"
#   type        = string
# }

variable "cognito_user_pool_arn" {
  description = "ARN of the Cognito User Pool"
  type        = string
}

variable "authorized_api_prefixes" {
  description = "Set of API prefixes that require Cognito authorization"
  type        = set(string)
  default     = []
}

#------------------------------------------------------------------------------
# Dependencies from network
#------------------------------------------------------------------------------

# variable "vpc_id" {
#   description = "VPC ID (from network)"
#   type        = string
#   default     = null
# }

variable "lambda_subnet_ids" {
  description = "Private subnet IDs for Lambda VPC configuration (from network)"
  type        = list(string)
  default     = []
}

variable "lambda_security_group_ids" {
  description = "Security group IDs for Lambda (from network)"
  type        = list(string)
  default     = []
}

variable "route53_zone_id" {
  description = "Route53 hosted zone ID (from network)"
  type        = string
}

#------------------------------------------------------------------------------
# Lambda Configuration
#------------------------------------------------------------------------------

variable "enable_vpc_access" {
  description = "Enable VPC access for Lambda functions"
  type        = bool
  default     = false
}

variable "lambda_runtime" {
  description = "Lambda runtime"
  type        = string
  default     = "nodejs20.x"
}

variable "lambda_architecture" {
  description = "Instruction set architecture for Lambda functions (x86_64 or arm64)"
  type        = string
  default     = "arm64"

  validation {
    condition     = contains(["x86_64", "arm64"], var.lambda_architecture)
    error_message = "lambda_architecture must be either 'x86_64' or 'arm64'."
  }
}

variable "lambda_timeout" {
  description = "Lambda timeout in seconds"
  type        = number
  default     = 30
}

variable "lambda_memory_size" {
  description = "Lambda memory size in MB"
  type        = number
  default     = 256
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 14
}

variable "use_placeholder_lambda" {
  description = "Use placeholder Lambda code for initial deployment (when S3 code doesn't exist yet)"
  type        = bool
  default     = false
}

# Lambda Resource Access — REMOVED (now per-lambda via `iam` block)
# See the `lambdas` variable below for per-function IAM configuration.

# Lambda Definitions Map
variable "lambdas" {
  description = <<-EOT
    Map of Lambda function configurations. Each key is the lambda name.

    Per-lambda IAM (least privilege):
      Use the `iam` block to grant each Lambda access to only the resources it needs.
      Secrets, SSM parameters, KMS keys, S3 buckets, DynamoDB tables, SQS queues,
      and Aurora clusters are specified individually per function.

    Internal SQS queue references:
      Use `sqs_send_to` and `sqs_receive_from` to reference internal SQS queues
      by name ("events", "order-placement", "order-results", "notifications").
      Lambdas with `sqs_trigger = true` automatically get receive on the events queue.
  EOT
  type = map(object({
    description                    = optional(string, "Lambda function")
    handler                        = optional(string, "index.handler")
    runtime                        = optional(string, null) # null = use var.lambda_runtime
    timeout                        = optional(number, null) # null = use var.lambda_timeout
    memory_size                    = optional(number, null) # null = use var.lambda_memory_size
    zip_path                       = optional(string, null) # Local path to zip file (Terraform uploads directly)
    s3_key                         = optional(string, null) # S3 key if already uploaded
    source_hash                    = optional(string, null) # Source code hash for updates
    environment                    = optional(map(string), {})
    api_path_prefix                = optional(string, null)     # API Gateway path prefix (e.g., "api1" -> /api1/*)
    sqs_trigger                    = optional(bool, false)      # Enable SQS event source mapping (auto-grants receive on events queue)
    sqs_send_to                    = optional(list(string), []) # Internal SQS queue names to send to
    sqs_receive_from               = optional(list(string), []) # Internal SQS queue names to receive from
    reserved_concurrent_executions = optional(number, -1)

    authorization        = optional(string, "NONE")   # "NONE" or "COGNITO_USER_POOLS"
    authorization_scopes = optional(list(string), []) # e.g., ["results/write", "orders/read"]

    # Per-lambda IAM permissions (least privilege)
    # Each Lambda gets its own IAM role with only these permissions.
    iam = optional(object({
      secrets_arns                = optional(list(string), []) # Secrets Manager ARNs this Lambda can read
      ssm_parameter_arns          = optional(list(string), []) # SSM Parameter Store ARNs
      kms_key_arns                = optional(list(string), []) # Additional KMS keys (shared KMS key always included)
      s3_bucket_arns              = optional(list(string), []) # S3 bucket ARNs
      dynamodb_table_arns         = optional(list(string), []) # DynamoDB table ARNs
      sqs_send_queue_arns         = optional(list(string), []) # External SQS ARNs to send to
      sqs_receive_queue_arns      = optional(list(string), []) # External SQS ARNs to receive from
      aurora_cluster_resource_ids = optional(list(string), []) # Aurora cluster resource IDs for IAM DB auth
      custom_policies             = optional(map(string), {})  # Custom IAM policy JSON documents
      managed_policy_arns         = optional(list(string), []) # Additional managed policy ARNs
    }), {})
  }))
  default = {}

  # Example:
  # lambdas = {
  #   "api1-handler" = {
  #     description     = "User service API"
  #     api_path_prefix = "api1"
  #     iam = {
  #       secrets_arns               = ["arn:aws:secretsmanager:eu-west-2:123:secret:my-secret-*"]
  #       aurora_cluster_resource_ids = ["cluster-ABC123"]
  #     }
  #   }
  #   "sqs-processor" = {
  #     description  = "SQS message processor"
  #     sqs_trigger  = true
  #     sqs_send_to  = ["notifications"]
  #     iam = {
  #       secrets_arns = ["arn:aws:secretsmanager:eu-west-2:123:secret:api-key-*"]
  #     }
  #   }
  # }
}

# Base path for lambda zip files (relative to terraform source)
variable "lambdas_base_path" {
  description = "Base path where lambda zip files are located"
  type        = string
  default     = "../../../examples/lambdas"
}

#------------------------------------------------------------------------------
# API Gateway Configuration
#------------------------------------------------------------------------------

variable "api_stage_name" {
  description = "API Gateway stage name"
  type        = string
  default     = "v1"
}

variable "api_endpoint_type" {
  description = "API Gateway endpoint type"
  type        = string
  default     = "REGIONAL"
}

variable "api_throttling_burst_limit" {
  description = "API Gateway throttling burst limit"
  type        = number
  default     = 1000
}

variable "api_throttling_rate_limit" {
  description = "API Gateway throttling rate limit"
  type        = number
  default     = 2000
}

#------------------------------------------------------------------------------
# Custom Domain Configuration
# Single domain for everything: dev1.hometest.service.nhs.uk
# - / -> SPA
# - /api1/* -> API Gateway 1
# - /api2/* -> API Gateway 2
#------------------------------------------------------------------------------

variable "custom_domain_name" {
  description = "Custom domain name for the environment (e.g., dev1.hometest.service.nhs.uk)"
  type        = string
  default     = null
}

variable "acm_certificate_arn" {
  description = "ACM certificate ARN for CloudFront (us-east-1, from shared_services)"
  type        = string
  default     = null
}

variable "api_custom_domain_name" {
  description = "Custom domain name for API Gateway (e.g., api-dev.poc.hometest.service.nhs.uk). API traffic is served directly from this domain instead of through CloudFront."
  type        = string
  default     = null
}

variable "cors_allowed_origin" {
  description = <<-EOT
    The exact origin allowed for CORS preflight (OPTIONS) responses on API Gateway.
    Must match the SPA domain (e.g., https://uat.hometest.service.nhs.uk).
    When credentials (cookies) are used, Access-Control-Allow-Origin cannot be '*'.
    If null, defaults to '*' (only safe when credentials are not used).
  EOT
  type        = string
  default     = null
}

variable "acm_regional_certificate_arn" {
  description = "ARN of the shared regional ACM certificate (from shared_services) for API Gateway custom domain. Used when create_api_certificate = false (default for POC wildcard cert pattern)."
  type        = string
  default     = null
}

variable "create_cloudfront_certificate" {
  description = <<-EOT
    When true, create a dedicated us-east-1 ACM certificate for var.custom_domain_name.
    Use for environments where the SPA domain is not covered by the shared wildcard cert.

    POC pattern  (create_cloudfront_certificate = false):
      Shared cert: *.poc.hometest.service.nhs.uk  (from shared_services, us-east-1)
      SPA:         dev.poc.hometest.service.nhs.uk  ← covered

    Custom pattern (create_cloudfront_certificate = true):
      Shared cert: *.poc.hometest.service.nhs.uk  does NOT cover dev.hometest.service.nhs.uk
      SPA:         dev.hometest.service.nhs.uk     ← dedicated cert created here in us-east-1
  EOT
  type        = bool
  default     = false
}

variable "create_api_certificate" {
  description = <<-EOT
    When true, create a dedicated regional ACM certificate for var.api_custom_domain_name.
    Use for environments where the API domain is not covered by the shared wildcard cert.

    POC pattern  (create_api_certificate = false):
      Shared cert: *.poc.hometest.service.nhs.uk
      SPA:         dev.poc.hometest.service.nhs.uk      ← covered
      API:         api-dev.poc.hometest.service.nhs.uk  ← covered (single-level)

    Custom pattern (create_api_certificate = true):
      Shared cert: *.hometest.service.nhs.uk
      SPA:         dev.hometest.service.nhs.uk          ← covered
      API:         api.dev.hometest.service.nhs.uk      ← NOT covered (two-level), cert created here
  EOT
  type        = bool
  default     = false
}

#------------------------------------------------------------------------------
# CloudFront Configuration
#------------------------------------------------------------------------------

variable "cloudfront_price_class" {
  description = "CloudFront price class"
  type        = string
  default     = "PriceClass_100"
}

variable "enable_cloudfront_logging" {
  description = "Enable CloudFront access logging"
  type        = bool
  default     = false
}

variable "cloudfront_logging_bucket_domain_name" {
  description = "S3 bucket domain name for CloudFront access logs"
  type        = string
  default     = null
}

#------------------------------------------------------------------------------
# Security Configuration
#------------------------------------------------------------------------------

variable "content_security_policy" {
  description = "Content Security Policy header"
  type        = string
  default     = "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; font-src 'self' data:; connect-src 'self' https:; frame-ancestors 'none';"
}

variable "permissions_policy" {
  description = "Permissions Policy header"
  type        = string
  default     = "accelerometer=(), camera=(), geolocation=(), gyroscope=(), magnetometer=(), microphone=(), payment=(), usb=()"
}

variable "geo_restriction_type" {
  description = "Geo restriction type (whitelist, blacklist, none)"
  type        = string
  default     = "none"
}

variable "geo_restriction_locations" {
  description = "List of country codes for geo restriction"
  type        = list(string)
  default     = []
}

################################################################################
# Region Configuration
################################################################################

variable "aws_allowed_regions" {
  description = "List of AWS regions allowed for resource deployment"
  type        = list(string)
  default     = ["eu-west-2", "us-east-1"]
}
