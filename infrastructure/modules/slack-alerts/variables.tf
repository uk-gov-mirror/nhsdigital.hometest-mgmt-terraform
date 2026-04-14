################################################################################
# Slack Alerts Module Variables
################################################################################

variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "aws_account_shortname" {
  description = "AWS account short name/alias used in resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "slack_webhook_secret_name" {
  description = "Name of the AWS Secrets Manager secret containing the Slack incoming webhook URL"
  type        = string
}

variable "slack_channel_name" {
  description = "Slack channel name for tagging and log context (e.g. hometest-ops-alerts)"
  type        = string
  default     = "hometest-ops-alerts"
}

variable "sns_topic_arns" {
  description = "List of SNS topic ARNs to subscribe the Slack notifier Lambda to"
  type        = list(string)
  default     = []
}

variable "kms_key_arn" {
  description = "ARN of the KMS key used to encrypt the Secrets Manager secret (null if using default key)"
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
