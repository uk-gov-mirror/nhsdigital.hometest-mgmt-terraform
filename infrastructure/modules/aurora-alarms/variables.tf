################################################################################
# Aurora PostgreSQL Alarms Module Variables
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

variable "cluster_identifier" {
  description = "Aurora DB cluster identifier"
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
  default     = 2
}

variable "alarm_cpu_threshold" {
  description = "CPU utilisation percentage threshold"
  type        = number
  default     = 80
}

variable "alarm_freeable_memory_threshold_mb" {
  description = "Freeable memory threshold in MB (alarm when below)"
  type        = number
  default     = 256
}

variable "alarm_max_connections_threshold" {
  description = "Maximum database connections threshold"
  type        = number
  default     = 100
}

variable "create_replica_lag_alarm" {
  description = "Create replica lag alarm (only if multi-AZ read replicas exist)"
  type        = bool
  default     = false
}

variable "alarm_replica_lag_threshold_ms" {
  description = "Maximum acceptable replica lag in milliseconds"
  type        = number
  default     = 100
}

variable "alarm_max_capacity_threshold" {
  description = "Maximum ACU threshold for Serverless v2 capacity alarm"
  type        = number
  default     = 8
}

variable "alarm_free_storage_threshold_gb" {
  description = "Free local storage threshold in GB (alarm when below)"
  type        = number
  default     = 5
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
