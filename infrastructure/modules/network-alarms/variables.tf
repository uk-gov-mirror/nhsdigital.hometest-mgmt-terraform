################################################################################
# Network Alarms Module Variables
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

variable "nat_gateway_ids" {
  description = "Map of logical name to NAT Gateway ID (e.g., { az1 = 'nat-xxx', az2 = 'nat-yyy' })"
  type        = map(string)
  default     = {}
}

variable "firewall_name" {
  description = "Network Firewall name (null to skip firewall alarms)"
  type        = string
  default     = null
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

variable "alarm_nat_packets_drop_threshold" {
  description = "Threshold for NAT Gateway packets drop alarm"
  type        = number
  default     = 100
}

variable "alarm_firewall_dropped_threshold" {
  description = "Threshold for Network Firewall dropped packets alarm"
  type        = number
  default     = 100
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
