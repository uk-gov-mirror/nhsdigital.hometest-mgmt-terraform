################################################################################
# API Gateway Module Variables
################################################################################

# Required Variables
variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "api_name_suffix" {
  description = "Suffix for API name (e.g., api1, api2). If null, uses 'api'"
  type        = string
  default     = null
}

# API Configuration
variable "description" {
  description = "Description of the API"
  type        = string
  default     = "REST API Gateway"
}

variable "stage_name" {
  description = "Name of the deployment stage"
  type        = string
  default     = "v1"
}

variable "endpoint_type" {
  description = "Endpoint type (REGIONAL, EDGE, or PRIVATE)"
  type        = string
  default     = "REGIONAL"

  validation {
    condition     = contains(["REGIONAL", "EDGE", "PRIVATE"], var.endpoint_type)
    error_message = "Endpoint type must be REGIONAL, EDGE, or PRIVATE."
  }
}

variable "minimum_compression_size" {
  description = "Minimum response size to compress (bytes). Set to -1 to disable."
  type        = number
  default     = 10240
}

# Logging Configuration
variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
}

variable "logging_level" {
  description = "Logging level (OFF, ERROR, INFO)"
  type        = string
  default     = "INFO"

  validation {
    condition     = contains(["OFF", "ERROR", "INFO"], var.logging_level)
    error_message = "Logging level must be OFF, ERROR, or INFO."
  }
}

variable "data_trace_enabled" {
  description = "Enable data trace logging (WARNING: may log sensitive data)"
  type        = bool
  default     = false
}

variable "xray_tracing_enabled" {
  description = "Enable X-Ray tracing"
  type        = bool
  default     = true
}

variable "cloudwatch_kms_key_arn" {
  description = "ARN of KMS key for encrypting CloudWatch logs"
  type        = string
  default     = null
}

# Throttling Configuration
variable "throttling_burst_limit" {
  description = "API Gateway throttling burst limit"
  type        = number
  default     = 5000
}

variable "throttling_rate_limit" {
  description = "API Gateway throttling rate limit"
  type        = number
  default     = 10000
}

# Caching Configuration
variable "cache_cluster_enabled" {
  description = "Enable API Gateway cache cluster"
  type        = bool
  default     = false
}

variable "cache_cluster_size" {
  description = "Size of the cache cluster (0.5, 1.6, 6.1, 13.5, 28.4, 58.2, 118, 237)"
  type        = string
  default     = "0.5"
}

variable "caching_enabled" {
  description = "Enable method-level caching"
  type        = bool
  default     = false
}

variable "cache_ttl_seconds" {
  description = "Cache TTL in seconds"
  type        = number
  default     = 300
}

# Security Configuration
variable "waf_web_acl_arn" {
  description = "ARN of WAF Web ACL to associate with the API Gateway"
  type        = string
  default     = null
}

# Custom Domain Configuration
variable "custom_domain_name" {
  description = "Custom domain name for the API"
  type        = string
  default     = null
}

variable "acm_certificate_arn" {
  description = "ARN of ACM certificate for custom domain"
  type        = string
  default     = null
}

variable "base_path_mapping" {
  description = "Base path for custom domain mapping"
  type        = string
  default     = ""
}

# Deployment Configuration
variable "create_deployment" {
  description = "Whether to create the API Gateway deployment (set to false if managing deployment externally)"
  type        = bool
  default     = false
}

variable "deployment_triggers" {
  description = "Map of triggers for redeployment (only used if create_deployment is true)"
  type        = map(string)
  default     = {}
}

# Mutual TLS (mTLS) Configuration
variable "mutual_tls_authentication" {
  description = "Mutual TLS authentication configuration for the custom domain. Requires a truststore in S3 containing client CA certificates."
  type = object({
    truststore_uri     = string
    truststore_version = optional(string)
  })
  default = null
}

# Tags
variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
