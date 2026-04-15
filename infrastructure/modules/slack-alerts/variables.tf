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

variable "slack_workspace_id" {
  description = "Slack workspace (team) ID. Found in AWS Chatbot console after authorizing the workspace."
  type        = string
}

variable "slack_channels" {
  description = <<-EOT
    Map of Slack channel configurations. Each key is a logical name for the channel.
    channel_id     = Slack channel ID (right-click channel → View channel details → copy ID)
    sns_topic_arns = List of SNS topic ARNs to subscribe this channel to
  EOT
  type = map(object({
    channel_id     = string
    sns_topic_arns = list(string)
  }))
  default = {}
}

variable "logging_level" {
  description = "Logging level for AWS Chatbot (ERROR, INFO, NONE)"
  type        = string
  default     = "ERROR"

  validation {
    condition     = contains(["ERROR", "INFO", "NONE"], var.logging_level)
    error_message = "Logging level must be ERROR, INFO, or NONE."
  }
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
