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
# Network Configuration - References from Network Module
# VPC and DB subnet group are passed from Terragrunt dependency on network module
################################################################################
variable "vpc_id" {
  description = "VPC ID from network module (passed via Terragrunt dependency)"
  type        = string
}

variable "allowed_cidr_blocks" {
  description = "List of CIDR blocks allowed to connect to the database"
  type        = list(string)
  default     = []
}

variable "allowed_security_group_ids" {
  description = "List of security group IDs allowed to connect to the database"
  type        = list(string)
  default     = []
}

variable "publicly_accessible" {
  description = "Whether the database should be publicly accessible"
  type        = bool
  default     = false
}

################################################################################
# PostgreSQL Configuration
################################################################################
variable "kms_key_id" {
  description = "The ARN for the KMS encryption key"
  type        = string
  default     = ""
}

variable "master_user_secret_kms_key_id" {
  description = "The ARN of the KMS key used to encrypt the master user password secret in Secrets Manager"
  type        = string
  default     = null
}

# Aurora module requires engine_version for the database engine version
variable "engine_version" {
  description = "PostgreSQL engine version"
  type        = string
  default     = "17.9"
}
# Aurora module requires db_subnet_group_name if not creating a new subnet group
variable "db_subnet_group_name" {
  description = "Name of the DB subnet group to use for the Aurora cluster. If not provided, the module will attempt to create one."
  type        = string
  default     = null
}

variable "serverlessv2_min_capacity" {
  description = "Minimum Aurora capacity units (ACUs) for Aurora Serverless v2"
  type        = number
  default     = 0.5
}

variable "serverlessv2_max_capacity" {
  description = "Maximum Aurora capacity units (ACUs) for Aurora Serverless v2"
  type        = number
  default     = 4
}


variable "storage_encrypted" {
  description = "Specifies whether the DB instance is encrypted"
  type        = bool
  default     = true
}

################################################################################
# Database Configuration
################################################################################
variable "db_name" {
  description = "The name of the database to create when the DB instance is created"
  type        = string
  default     = "postgres"
}

variable "username" {
  description = "Username for the master DB user"
  type        = string
  default     = "postgres"
}

################################################################################
# High Availability Configuration
################################################################################
variable "number_of_instances" {
  description = "Number of Aurora instances to create in the cluster"
  type        = number
  default     = 1
}

################################################################################
# Backup Configuration
################################################################################
variable "backup_retention_period" {
  description = "The days to retain backups for"
  type        = number
  default     = 7
}

variable "backup_window" {
  description = "The daily time range during which automated backups are created"
  type        = string
  default     = "03:00-04:00"
}

variable "maintenance_window" {
  description = "The window to perform maintenance in"
  type        = string
  default     = "Mon:04:00-Mon:05:00"
}

variable "skip_final_snapshot" {
  description = "Determines whether a final DB snapshot is created before the DB instance is deleted"
  type        = bool
  default     = false
}

variable "deletion_protection" {
  description = "If the DB instance should have deletion protection enabled"
  type        = bool
  default     = false
}


################################################################################
# Update Configuration
################################################################################
variable "apply_immediately" {
  description = "Specifies whether any database modifications are applied immediately"
  type        = bool
  default     = false
}

################################################################################
# IAM Authentication
################################################################################
variable "enable_iam_auth" {
  description = "Enable IAM database authentication for the Aurora cluster"
  type        = bool
  default     = false
}

################################################################################
# Data API
################################################################################
variable "enable_http_endpoint" {
  description = "Enable the Data API for Aurora Serverless v2. Allows querying the database from AWS Console without managing connections."
  type        = bool
  default     = false
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
# Alerting
################################################################################
variable "sns_alerts_critical_topic_arn" {
  description = "ARN of the critical alerts SNS topic (from shared_services). When set, creates CloudWatch alarms."
  type        = string
  default     = null
}

variable "enable_ok_actions" {
  description = "Send notifications when alarms return to OK state (enable for prod, disable for dev to reduce noise)"
  type        = bool
  default     = false
}

################################################################################
# Region Configuration
################################################################################
variable "aws_allowed_regions" {
  description = "List of AWS regions allowed for resource deployment"
  type        = list(string)
  default     = ["eu-west-2", "us-east-1"]
}
