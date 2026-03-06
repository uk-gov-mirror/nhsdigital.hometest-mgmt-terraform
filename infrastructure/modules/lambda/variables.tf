################################################################################
# Lambda Module Variables
################################################################################

#------------------------------------------------------------------------------
# Required Variables
#------------------------------------------------------------------------------

variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "aws_account_shortname" {
  description = "AWS account short name/alias used in resource naming (e.g., poc, dev, prod)"
  type        = string
}

variable "function_name" {
  description = "Name of the Lambda function (will be prefixed with project and environment)"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

#------------------------------------------------------------------------------
# IAM Configuration (per-lambda least-privilege)
#------------------------------------------------------------------------------

variable "aws_account_id" {
  description = "AWS account ID (used for IAM policy resource ARNs)"
  type        = string
}

variable "aws_region" {
  description = "AWS region (used for IAM policy resource ARNs)"
  type        = string
}

variable "enable_vpc_access" {
  description = "Enable VPC access IAM permissions (ec2:CreateNetworkInterface, etc.)"
  type        = bool
  default     = false
}

variable "enable_xray" {
  description = "Enable X-Ray tracing IAM permissions"
  type        = bool
  default     = true
}

variable "restrict_to_account" {
  description = "Restrict role assumption to the specific AWS account"
  type        = bool
  default     = true
}

variable "max_session_duration" {
  description = "Maximum session duration for the IAM role in seconds"
  type        = number
  default     = 3600
}

variable "secrets_arns" {
  description = "List of Secrets Manager secret ARNs this Lambda can read"
  type        = list(string)
  default     = []
}

variable "ssm_parameter_arns" {
  description = "List of SSM Parameter Store ARNs this Lambda can read"
  type        = list(string)
  default     = []
}

variable "kms_key_arns" {
  description = "List of KMS key ARNs this Lambda can use for decryption"
  type        = list(string)
  default     = []
}

variable "s3_bucket_arns" {
  description = "List of S3 bucket ARNs this Lambda can access (read/write)"
  type        = list(string)
  default     = []
}

variable "dynamodb_table_arns" {
  description = "List of DynamoDB table ARNs this Lambda can access"
  type        = list(string)
  default     = []
}

variable "sqs_send_queue_arns" {
  description = "List of SQS queue ARNs this Lambda can send messages to"
  type        = list(string)
  default     = []
}

variable "sqs_receive_queue_arns" {
  description = "List of SQS queue ARNs this Lambda can receive/delete messages from"
  type        = list(string)
  default     = []
}

variable "aurora_cluster_resource_ids" {
  description = "List of Aurora cluster resource IDs for IAM database authentication (rds-db:connect)"
  type        = list(string)
  default     = []
}

variable "custom_policies" {
  description = "Map of custom IAM policy names to policy JSON documents"
  type        = map(string)
  default     = {}
}

variable "managed_policy_arns" {
  description = "List of managed IAM policy ARNs to attach to this Lambda's role"
  type        = list(string)
  default     = []
}

# Deployment Package
variable "s3_bucket" {
  description = "S3 bucket containing the Lambda deployment package (not required if use_placeholder is true)"
  type        = string
  default     = null
}

variable "s3_key" {
  description = "S3 key for the Lambda deployment package (not required if use_placeholder is true)"
  type        = string
  default     = null
}

variable "s3_object_version" {
  description = "S3 object version for the Lambda deployment package"
  type        = string
  default     = null
}

variable "filename" {
  description = "Path to the local zip file for Lambda deployment (Terraform uploads directly)"
  type        = string
  default     = null
}

variable "source_code_hash" {
  description = "Base64-encoded SHA256 hash of the deployment package"
  type        = string
  default     = null
}

variable "use_placeholder" {
  description = "Use placeholder code for initial deployment (useful when S3 code doesn't exist yet)"
  type        = bool
  default     = false
}

variable "placeholder_response" {
  description = "JSON response for placeholder Lambda (when use_placeholder is true)"
  type        = string
  default     = "{\"statusCode\": 200, \"body\": \"Placeholder - deploy actual code\"}"
}

variable "publish" {
  description = "Whether to publish creation/change as new Lambda function version"
  type        = bool
  default     = false
}

# Function Configuration
variable "description" {
  description = "Description of the Lambda function"
  type        = string
  default     = ""
}

variable "handler" {
  description = "Function entrypoint"
  type        = string
  default     = "index.handler"
}

variable "runtime" {
  description = "Lambda runtime"
  type        = string
  default     = "nodejs20.x"
}

variable "architectures" {
  description = "Instruction set architecture for the Lambda function (x86_64 or arm64)"
  type        = list(string)
  default     = ["arm64"]

  validation {
    condition     = length(var.architectures) == 1 && contains(["x86_64", "arm64"], var.architectures[0])
    error_message = "Architectures must be a single-element list of either 'x86_64' or 'arm64'."
  }
}

variable "layers" {
  description = "List of Lambda layer ARNs to attach (max 5)"
  type        = list(string)
  default     = []
}

variable "timeout" {
  description = "Function timeout in seconds"
  type        = number
  default     = 30
}

variable "memory_size" {
  description = "Function memory in MB"
  type        = number
  default     = 256
}

variable "reserved_concurrent_executions" {
  description = "Reserved concurrent executions (-1 for unreserved)"
  type        = number
  default     = -1
}

# Environment Variables
variable "environment_variables" {
  description = "Environment variables for the Lambda function"
  type        = map(string)
  default     = {}
}

# VPC Configuration
variable "vpc_subnet_ids" {
  description = "List of subnet IDs for VPC configuration"
  type        = list(string)
  default     = null
}

variable "vpc_security_group_ids" {
  description = "List of security group IDs for VPC configuration"
  type        = list(string)
  default     = null
}

# Encryption
variable "lambda_kms_key_arn" {
  description = "ARN of KMS key for encrypting environment variables"
  type        = string
  default     = null
}

variable "cloudwatch_kms_key_arn" {
  description = "ARN of KMS key for encrypting CloudWatch logs"
  type        = string
  default     = null
}

# Logging
variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
}

# CloudWatch Alarms

variable "create_cloudwatch_alarms" {
  description = "Create CloudWatch alarms for Lambda errors"
  type        = bool
  default     = true
}

variable "alarm_actions" {
  description = "List of ARNs to notify when an alarm triggers (e.g., SNS topics)"
  type        = list(string)
  default     = []
}

variable "alarm_period" {
  description = "Period in seconds over which to evaluate the Lambda error metric"
  type        = number
  default     = 300
}

variable "alarm_evaluation_periods" {
  description = "Number of periods over which to evaluate the Lambda error alarm"
  type        = number
  default     = 1
}

variable "alarm_error_threshold" {
  description = "Threshold for Lambda error alarm (number of errors per evaluation period)"
  type        = number
  default     = 1
}

# Tracing
variable "tracing_mode" {
  description = "X-Ray tracing mode (Active or PassThrough)"
  type        = string
  default     = "Active"

  validation {
    condition     = contains(["Active", "PassThrough"], var.tracing_mode)
    error_message = "Tracing mode must be either 'Active' or 'PassThrough'."
  }
}

# Dead Letter Queue
variable "dead_letter_target_arn" {
  description = "ARN of SQS queue or SNS topic for dead letter queue"
  type        = string
  default     = null
}

# Tags
variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
