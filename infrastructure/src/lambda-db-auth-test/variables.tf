variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID"
  type        = string
}

variable "aws_account_shortname" {
  description = "AWS account short name for resource naming"
  type        = string
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, uat)"
  type        = string
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}

variable "db_address" {
  description = "Aurora cluster endpoint"
  type        = string
}

variable "db_port" {
  description = "Aurora cluster port"
  type        = string
}

variable "db_name" {
  description = "Database name"
  type        = string
}

variable "db_schema" {
  description = "Database schema (e.g., hometest_uat)"
  type        = string
}

variable "subnet_ids" {
  description = "VPC subnet IDs for Lambda"
  type        = list(string)
}

variable "security_group_ids" {
  description = "Security group IDs for Lambda"
  type        = list(string)
}

variable "app_user_secret_name" {
  description = "Secrets Manager secret name for app_user password (for password auth fallback test)"
  type        = string
  default     = ""
}
