################################################################################
# WAF Alarms Module Variables
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

variable "aws_region" {
  description = "AWS region where the WAF is deployed"
  type        = string
}

variable "web_acl_name" {
  description = "Name of the WAFv2 Web ACL (used in CloudWatch dimensions)"
  type        = string
}

variable "waf_name_suffix" {
  description = "Suffix for alarm naming (e.g., 'regional', 'cloudfront')"
  type        = string
}

variable "alarm_actions" {
  description = "List of ARNs to notify when an alarm triggers (e.g., SNS topics)"
  type        = list(string)
  default     = []
}

variable "enable_ok_actions" {
  description = "Send notifications when alarm returns to OK state (set true for prod, false for dev to reduce noise)"
  type        = bool
  default     = false
}

variable "alarm_period" {
  description = "Period in seconds over which to evaluate each metric"
  type        = number
  default     = 300
}

variable "alarm_evaluation_periods" {
  description = "Number of periods over which to evaluate each alarm"
  type        = number
  default     = 1
}

variable "alarm_blocked_threshold" {
  description = "Threshold for blocked requests spike alarm"
  type        = number
  default     = 100
}

variable "rate_limit_metric_name" {
  description = "CloudWatch metric name for the rate-limiting WAF rule (null to skip)"
  type        = string
  default     = null
}

variable "sqli_metric_name" {
  description = "CloudWatch metric name for the SQL injection WAF rule (null to skip)"
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
