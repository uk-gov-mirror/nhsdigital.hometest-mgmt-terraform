################################################################################
# API Gateway Alarms Module Variables
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

variable "api_names" {
  description = "Set of API Gateway REST API names to create alarms for"
  type        = set(string)
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

variable "alarm_5xx_threshold" {
  description = "5XX error rate percentage threshold"
  type        = number
  default     = 1
}

variable "alarm_4xx_threshold" {
  description = "4XX error rate percentage threshold"
  type        = number
  default     = 10
}

variable "alarm_latency_threshold_ms" {
  description = "p99 latency threshold in milliseconds"
  type        = number
  default     = 3000
}

variable "alarm_integration_latency_threshold_ms" {
  description = "p99 integration latency threshold in milliseconds"
  type        = number
  default     = 2000
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
