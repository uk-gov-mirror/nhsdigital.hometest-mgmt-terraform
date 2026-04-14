################################################################################
# AWS Configuration
################################################################################
variable "aws_region" {
  description = "AWS region for resources"
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID"
  type        = string
}

variable "aws_account_shortname" {
  description = "AWS account short name/alias for resource naming"
  type        = string
}

################################################################################
# Project Configuration
################################################################################
variable "project_name" {
  description = "Project name used for resource naming"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
}

################################################################################
# Tags
################################################################################
variable "tags" {
  description = "Additional tags for all resources"
  type        = map(string)
  default     = {}
}

################################################################################
# Region Configuration
################################################################################
variable "aws_allowed_regions" {
  description = "List of AWS regions allowed for resource deployment"
  type        = list(string)
  default     = ["eu-west-2", "us-east-1"]
}

variable "db_username" {
  description = "Database username"
  type        = string
}

variable "db_address" {
  description = "Database address"
  type        = string
}

variable "db_port" {
  description = "Database port"
  type        = string
}

variable "db_name" {
  description = "Database name"
  type        = string
}

variable "db_cluster_id" {
  description = "DB CLuster ID"
  type        = string
}

variable "db_schema" {
  description = "Database schema name for environment isolation (e.g., hometest_dev, hometest_staging)"
  type        = string
  default     = "public"
}

variable "app_user_secret_name" {
  description = "Secrets Manager secret name to store the schema-scoped app_user credentials"
  type        = string
  default     = ""
}

variable "subnet_ids" {
  description = "List of subnet IDs for Lambda VPC config"
  type        = list(string)
}

variable "security_group_ids" {
  description = "List of security group IDs for Lambda VPC config"
  type        = list(string)
}

variable "kms_key_arn" {
  description = "ARN of the customer-managed KMS key for encrypting Secrets Manager secrets"
  type        = string
}

variable "use_iam_auth" {
  description = "Whether the goose migrator Lambda itself connects to Aurora using IAM auth instead of Secrets Manager password. The master user typically uses password auth, so this is usually false."
  type        = bool
  default     = false
}

variable "grant_rds_iam" {
  description = "Whether to GRANT rds_iam to the app_user so that app lambdas can use IAM token authentication. Independent of how the migrator itself connects."
  type        = bool
  default     = false
}

################################################################################
# Lambda Configuration
################################################################################
variable "goose_migrator_zip_path" {
  description = "Path to the pre-built goose-migrator zip file"
  type        = string
}
