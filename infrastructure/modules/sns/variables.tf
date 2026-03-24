################################################################################
# SNS Module Variables
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
  description = "Short name for the AWS account"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.aws_account_shortname))
    error_message = "AWS account shortname must contain only lowercase letters, numbers, and hyphens."
  }
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
# Topic Naming
#------------------------------------------------------------------------------

variable "topic_name_suffix" {
  description = "Suffix for topic name (e.g., alerts, notifications). If null, uses 'topic'"
  type        = string
  default     = null
}

variable "display_name" {
  description = "The display name for the SNS topic"
  type        = string
  default     = null
}

#------------------------------------------------------------------------------
# Topic Type (Standard / FIFO)
#------------------------------------------------------------------------------

variable "fifo_topic" {
  description = "Boolean indicating whether to create a FIFO topic"
  type        = bool
  default     = false
}

variable "content_based_deduplication" {
  description = "Enable content-based deduplication for FIFO topics"
  type        = bool
  default     = false
}

variable "fifo_throughput_scope" {
  description = "FIFO throughput scope (Topic or MessageGroup)"
  type        = string
  default     = null

  validation {
    condition     = var.fifo_throughput_scope == null || contains(["Topic", "MessageGroup"], var.fifo_throughput_scope)
    error_message = "FIFO throughput scope must be 'Topic' or 'MessageGroup'."
  }
}

#------------------------------------------------------------------------------
# Encryption
#------------------------------------------------------------------------------

variable "kms_master_key_id" {
  description = "ID of AWS KMS key for topic encryption. If not specified, uses SNS managed key"
  type        = string
  default     = null
}

#------------------------------------------------------------------------------
# Topic Policy
#------------------------------------------------------------------------------

variable "create_topic_policy" {
  description = "Create an SNS topic policy"
  type        = bool
  default     = true
}

variable "enable_default_topic_policy" {
  description = "Enable the default SNS topic policy"
  type        = bool
  default     = true
}

variable "topic_policy_statements" {
  description = "IAM policy statements for SNS topic access"
  type        = any
  default     = null
}

variable "topic_policy" {
  description = "Externally created fully-formed AWS policy as JSON"
  type        = string
  default     = null
}

#------------------------------------------------------------------------------
# Subscriptions
#------------------------------------------------------------------------------

variable "create_subscription" {
  description = "Create SNS subscriptions defined in subscriptions map"
  type        = bool
  default     = true
}

variable "subscriptions" {
  description = "Map of SNS subscriptions to create"
  type        = any
  default     = {}
}

#------------------------------------------------------------------------------
# Advanced Configuration
#------------------------------------------------------------------------------

variable "delivery_policy" {
  description = "SNS delivery policy JSON"
  type        = string
  default     = null
}

variable "data_protection_policy" {
  description = "Data protection policy JSON for the SNS topic"
  type        = string
  default     = null
}

variable "tracing_config" {
  description = "Tracing mode for the SNS topic (PassThrough or Active)"
  type        = string
  default     = null

  validation {
    condition     = var.tracing_config == null || contains(["PassThrough", "Active"], var.tracing_config)
    error_message = "Tracing config must be 'PassThrough' or 'Active'."
  }
}

variable "signature_version" {
  description = "Signature version for SNS messages (1 for SHA1, 2 for SHA256)"
  type        = number
  default     = null

  validation {
    condition     = var.signature_version == null || contains([1, 2], var.signature_version)
    error_message = "Signature version must be 1 or 2."
  }
}

#------------------------------------------------------------------------------
# Tags
#------------------------------------------------------------------------------

variable "tags" {
  description = "Additional tags for all resources"
  type        = map(string)
  default     = {}
}
