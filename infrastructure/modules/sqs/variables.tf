################################################################################
# SQS Module Variables
################################################################################

#------------------------------------------------------------------------------
# Required Variables
#------------------------------------------------------------------------------

variable "project_name" {
  description = "Name of the project"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "aws_account_shortname" {
  description = "Short name of the AWS account (e.g. poc, dev, prod)"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "Environment must contain only lowercase letters, numbers, and hyphens."
  }
}

#------------------------------------------------------------------------------
# Queue Naming
#------------------------------------------------------------------------------

variable "queue_name_suffix" {
  description = "Suffix for queue name (e.g., orders, notifications). If null, uses 'queue'"
  type        = string
  default     = null
}

#------------------------------------------------------------------------------
# Queue Type
#------------------------------------------------------------------------------

variable "fifo_queue" {
  description = "Boolean to enable FIFO queue (First-In-First-Out)"
  type        = bool
  default     = false
}

variable "content_based_deduplication" {
  description = "Enable content-based deduplication for FIFO queues"
  type        = bool
  default     = false
}

variable "deduplication_scope" {
  description = "Specifies whether message deduplication occurs at message group or queue level (messageGroup or queue)"
  type        = string
  default     = null

  validation {
    condition     = var.deduplication_scope == null || contains(["messageGroup", "queue"], var.deduplication_scope)
    error_message = "Deduplication scope must be 'messageGroup' or 'queue'."
  }
}

variable "fifo_throughput_limit" {
  description = "Specifies FIFO throughput limit (perQueue or perMessageGroupId)"
  type        = string
  default     = null

  validation {
    condition     = var.fifo_throughput_limit == null || contains(["perQueue", "perMessageGroupId"], var.fifo_throughput_limit)
    error_message = "FIFO throughput limit must be 'perQueue' or 'perMessageGroupId'."
  }
}

#------------------------------------------------------------------------------
# Encryption
#------------------------------------------------------------------------------

variable "kms_master_key_id" {
  description = "ID of AWS KMS key for queue encryption. If not specified, uses SQS managed encryption (if enabled)"
  type        = string
  default     = null
}

variable "kms_data_key_reuse_period_seconds" {
  description = "Length of time (seconds) for which SQS can reuse a data key (60-86400)"
  type        = number
  default     = 300

  validation {
    condition     = var.kms_data_key_reuse_period_seconds >= 60 && var.kms_data_key_reuse_period_seconds <= 86400
    error_message = "KMS data key reuse period must be between 60 and 86400 seconds."
  }
}

variable "sqs_managed_sse_enabled" {
  description = "Enable SQS managed server-side encryption (SSE-SQS)"
  type        = bool
  default     = true
}

#------------------------------------------------------------------------------
# Message Configuration
#------------------------------------------------------------------------------

variable "visibility_timeout_seconds" {
  description = "Visibility timeout for the queue (0-43200 seconds)"
  type        = number
  default     = 30

  validation {
    condition     = var.visibility_timeout_seconds >= 0 && var.visibility_timeout_seconds <= 43200
    error_message = "Visibility timeout must be between 0 and 43200 seconds."
  }
}

variable "message_retention_seconds" {
  description = "Time messages are retained in queue (60-1209600 seconds / 1 min - 14 days)"
  type        = number
  default     = 345600 # 4 days

  validation {
    condition     = var.message_retention_seconds >= 60 && var.message_retention_seconds <= 1209600
    error_message = "Message retention must be between 60 and 1209600 seconds."
  }
}

variable "max_message_size" {
  description = "Maximum message size in bytes (1024-262144)"
  type        = number
  default     = 262144 # 256 KB

  validation {
    condition     = var.max_message_size >= 1024 && var.max_message_size <= 262144
    error_message = "Max message size must be between 1024 and 262144 bytes."
  }
}

variable "delay_seconds" {
  description = "Delay before messages become available (0-900 seconds)"
  type        = number
  default     = 0

  validation {
    condition     = var.delay_seconds >= 0 && var.delay_seconds <= 900
    error_message = "Delay seconds must be between 0 and 900."
  }
}

variable "receive_wait_time_seconds" {
  description = "Long polling wait time for ReceiveMessage (0-20 seconds)"
  type        = number
  default     = 0

  validation {
    condition     = var.receive_wait_time_seconds >= 0 && var.receive_wait_time_seconds <= 20
    error_message = "Receive wait time must be between 0 and 20 seconds."
  }
}

#------------------------------------------------------------------------------
# Dead Letter Queue (DLQ) Configuration
#------------------------------------------------------------------------------

variable "create_dlq" {
  description = "Create a Dead Letter Queue for failed messages"
  type        = bool
  default     = true
}

variable "max_receive_count" {
  description = "Maximum number of receives before message moves to DLQ"
  type        = number
  default     = 3

  validation {
    condition     = var.max_receive_count >= 1
    error_message = "Max receive count must be at least 1."
  }
}

variable "dlq_message_retention_seconds" {
  description = "Time messages are retained in DLQ (60-1209600 seconds / 1 min - 14 days)"
  type        = number
  default     = 1209600 # 14 days

  validation {
    condition     = var.dlq_message_retention_seconds >= 60 && var.dlq_message_retention_seconds <= 1209600
    error_message = "DLQ message retention must be between 60 and 1209600 seconds."
  }
}

variable "enable_dlq_redrive" {
  description = "Allow messages to be redriven from DLQ back to source queue"
  type        = bool
  default     = true
}

#------------------------------------------------------------------------------
# Queue Policy
#------------------------------------------------------------------------------

variable "create_queue_policy" {
  description = "Create an IAM policy for the queue"
  type        = bool
  default     = false
}

variable "queue_policy_statements" {
  description = "IAM policy statements for queue access"
  type        = any
  default     = {}
}

#------------------------------------------------------------------------------
# CloudWatch Alarms
#------------------------------------------------------------------------------

variable "create_cloudwatch_alarms" {
  description = "Create CloudWatch alarms for queue monitoring"
  type        = bool
  default     = true
}

variable "alarm_actions" {
  description = "List of ARNs to notify when alarm triggers (e.g., SNS topics)"
  type        = list(string)
  default     = []
}

variable "alarm_period" {
  description = "Period in seconds over which to evaluate metric"
  type        = number
  default     = 300
}

variable "alarm_evaluation_periods" {
  description = "Number of periods over which to evaluate alarm"
  type        = number
  default     = 2
}

variable "alarm_age_threshold" {
  description = "Threshold in seconds for oldest message age alarm"
  type        = number
  default     = 600 # 10 minutes
}

variable "alarm_depth_threshold" {
  description = "Threshold for queue depth alarm (number of messages)"
  type        = number
  default     = 1000
}

variable "alarm_dlq_threshold" {
  description = "Threshold for DLQ alarm (number of messages)"
  type        = number
  default     = 0 # Alert on any message in DLQ
}

#------------------------------------------------------------------------------
# Resource Group
#------------------------------------------------------------------------------

variable "create_resource_group" {
  description = "Create an AWS Resource Group for SQS resources"
  type        = bool
  default     = true
}

#------------------------------------------------------------------------------
# Tags
#------------------------------------------------------------------------------

variable "tags" {
  description = "Additional tags for all resources"
  type        = map(string)
  default     = {}
}
