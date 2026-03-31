################################################################################
# ECS Cluster Variables
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
  description = "AWS account short name for resource naming"
  type        = string
}

variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "vpc_id" {
  description = "VPC ID for service discovery namespace"
  type        = string
}

variable "kms_key_arn" {
  description = "ARN of KMS key for encryption"
  type        = string
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
}

################################################################################
# Shared ALB Configuration
################################################################################

variable "enable_alb" {
  description = "Create a shared internet-facing ALB for ECS services"
  type        = bool
  default     = true
}

variable "public_subnet_ids" {
  description = "Public subnet IDs for the internet-facing ALB (protected by network firewall)"
  type        = list(string)
  default     = []
}

variable "acm_regional_certificate_arn" {
  description = "ARN of the shared regional ACM wildcard certificate for HTTPS"
  type        = string
  default     = null
}

variable "waf_regional_arn" {
  description = "ARN of the regional WAF Web ACL to attach to the ALB"
  type        = string
  default     = null
}
