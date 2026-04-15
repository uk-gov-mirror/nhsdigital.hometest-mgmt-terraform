################################################################################
# Shared Services Variables
################################################################################

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID for resources"
  type        = string
}

variable "aws_account_shortname" {
  description = "AWS account short name/alias for resource naming"
  type        = string
}

variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment name (core for shared services)"
  type        = string
  default     = "core"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

################################################################################
# KMS Configuration
################################################################################

variable "kms_deletion_window_days" {
  description = "Number of days before KMS key is deleted"
  type        = number
  default     = 30
}

################################################################################
# WAF Configuration
################################################################################

variable "waf_rate_limit" {
  description = "Rate limit for WAF (requests per 5 minutes per IP)"
  type        = number
  default     = 2000
}

variable "waf_wiremock_allowed_host_prefix" {
  description = "Host header prefix to allow through WAF without inspection (e.g. 'wiremock-'). When set, requests whose Host header starts with this value are allowed by the WAF. Enables WireMock to use the shared ALB instead of a dedicated no-WAF ALB."
  type        = string
  default     = null
}

variable "waf_log_retention_days" {
  description = "Days to retain WAF logs"
  type        = number
  default     = 30
}

################################################################################
# ACM Configuration
################################################################################

variable "create_acm_certificates" {
  description = "Whether to create ACM certificates"
  type        = bool
  default     = true
}

variable "domain_name" {
  description = "Base domain name for certificates (e.g., hometest.service.nhs.uk)"
  type        = string
}

variable "route53_zone_id" {
  description = "Route53 zone ID for DNS validation"
  type        = string
}

################################################################################
# Deployment Artifacts
################################################################################

# variable "artifact_retention_days" {
#   description = "Days to retain old artifact versions"
#   type        = number
#   default     = 30
# }

################################################################################
# Developer IAM
################################################################################

variable "developer_account_arns" {
  description = "List of AWS account ARNs allowed to assume the developer role"
  type        = list(string)
  default     = []
}

################################################################################
# SNS Configuration
################################################################################

variable "sns_alerts_email_subscriptions" {
  description = "List of email addresses to subscribe to the shared alerts SNS topic (requires subscription confirmation)"
  type        = list(string)
  default     = []
}

variable "require_mfa" {
  description = "Require MFA for developer role assumption"
  type        = bool
  default     = true
}

################################################################################
# Slack Alerts Configuration
################################################################################

variable "enable_slack_alerts" {
  description = "Enable AWS Chatbot Slack integration for alert notifications"
  type        = bool
  default     = false
}

variable "enable_ok_actions" {
  description = "Send notifications when alarms return to OK state (enable for prod, disable for dev to reduce noise)"
  type        = bool
  default     = false
}

variable "slack_workspace_id" {
  description = "Slack workspace (team) ID. Authorize workspace in AWS Chatbot console first."
  type        = string
  default     = ""
}

variable "slack_channel_id_critical" {
  description = "Slack channel ID for critical (P1) alerts"
  type        = string
  default     = ""
}

variable "slack_channel_id_warning" {
  description = "Slack channel ID for warning (P2) alerts"
  type        = string
  default     = ""
}

variable "slack_channel_id_security" {
  description = "Slack channel ID for security alerts (WAF blocks, SQLi, rate limiting)"
  type        = string
  default     = ""
}

################################################################################
# Network Alarm Inputs
# Passed from network dependency to create alarms for NAT Gateways and Firewall
################################################################################

variable "nat_gateway_ids" {
  description = "List of NAT Gateway IDs from the network module"
  type        = list(string)
  default     = []
}

variable "network_firewall_name" {
  description = "Name of the Network Firewall (null if not enabled)"
  type        = string
  default     = null
}

################################################################################
# mTLS Configuration
################################################################################

variable "enable_mtls" {
  description = "Enable mutual TLS infrastructure — creates CA, client cert, S3 truststore, and Secrets Manager entries"
  type        = bool
  default     = false
}

variable "mtls_ca_validity_hours" {
  description = "Validity period for the mTLS CA certificate in hours (default: 10 years)"
  type        = number
  default     = 87600
}

variable "mtls_client_validity_hours" {
  description = "Validity period for the mTLS client certificate in hours (default: 1 year)"
  type        = number
  default     = 8760
}

#------------------------------------------------------------------------------
# Cognito User Pool Configuration
#------------------------------------------------------------------------------

variable "enable_cognito" {
  description = "Enable AWS Cognito User Pool for authentication"
  type        = bool
  default     = false
}

variable "cognito_allow_admin_create_user_only" {
  description = "Only allow administrators to create users (disable self-registration)"
  type        = bool
  default     = false
}

variable "cognito_invite_email_subject" {
  description = "Email subject for user invitation emails"
  type        = string
  default     = "Your temporary password"
}

variable "cognito_invite_email_message" {
  description = "Email message for user invitation emails. Must contain {username} and {####} placeholders."
  type        = string
  default     = "Your username is {username} and temporary password is {####}."
}

variable "cognito_invite_sms_message" {
  description = "SMS message for user invitation. Must contain {username} and {####} placeholders."
  type        = string
  default     = "Your username is {username} and temporary password is {####}."
}

variable "cognito_auto_verified_attributes" {
  description = "Attributes to be auto-verified (email, phone_number, or both)"
  type        = list(string)
  default     = ["email"]

  validation {
    condition     = alltrue([for attr in var.cognito_auto_verified_attributes : contains(["email", "phone_number"], attr)])
    error_message = "Auto-verified attributes must be 'email', 'phone_number', or both."
  }
}

variable "cognito_deletion_protection" {
  description = "Enable deletion protection for the user pool"
  type        = bool
  default     = true
}

variable "cognito_device_challenge_required" {
  description = "Require device challenge on new devices"
  type        = bool
  default     = true
}

variable "cognito_device_remember_on_prompt" {
  description = "Only remember devices when user opts in"
  type        = bool
  default     = true
}

variable "cognito_email_sending_account" {
  description = "Email sending account type (COGNITO_DEFAULT or DEVELOPER)"
  type        = string
  default     = "COGNITO_DEFAULT"

  validation {
    condition     = contains(["COGNITO_DEFAULT", "DEVELOPER"], var.cognito_email_sending_account)
    error_message = "Email sending account must be COGNITO_DEFAULT or DEVELOPER."
  }
}

variable "cognito_ses_email_identity_arn" {
  description = "ARN of SES verified email identity (required if email_sending_account is DEVELOPER)"
  type        = string
  default     = null
}

variable "cognito_from_email_address" {
  description = "From email address for Cognito emails (requires DEVELOPER email sending account)"
  type        = string
  default     = null
}

variable "cognito_mfa_configuration" {
  description = "MFA configuration (OFF, ON, OPTIONAL)"
  type        = string
  default     = "OPTIONAL"

  validation {
    condition     = contains(["OFF", "ON", "OPTIONAL"], var.cognito_mfa_configuration)
    error_message = "MFA configuration must be OFF, ON, or OPTIONAL."
  }
}

variable "cognito_password_minimum_length" {
  description = "Minimum password length"
  type        = number
  default     = 12

  validation {
    condition     = var.cognito_password_minimum_length >= 8 && var.cognito_password_minimum_length <= 256
    error_message = "Password minimum length must be between 8 and 256."
  }
}

variable "cognito_password_require_lowercase" {
  description = "Require lowercase letters in password"
  type        = bool
  default     = true
}

variable "cognito_password_require_numbers" {
  description = "Require numbers in password"
  type        = bool
  default     = true
}

variable "cognito_password_require_symbols" {
  description = "Require symbols in password"
  type        = bool
  default     = true
}

variable "cognito_password_require_uppercase" {
  description = "Require uppercase letters in password"
  type        = bool
  default     = true
}

variable "cognito_temporary_password_validity_days" {
  description = "Number of days temporary passwords are valid"
  type        = number
  default     = 7
}

variable "cognito_custom_attributes" {
  description = "List of custom user attributes"
  type = list(object({
    name                     = string
    attribute_data_type      = string # String, Number, DateTime, Boolean
    developer_only_attribute = optional(bool, false)
    mutable                  = optional(bool, true)
    required                 = optional(bool, false)
    min_length               = optional(number, 0)
    max_length               = optional(number, 2048)
    min_value                = optional(number)
    max_value                = optional(number)
  }))
  default = []
}

variable "cognito_username_case_sensitive" {
  description = "Whether usernames are case sensitive"
  type        = bool
  default     = false
}

variable "cognito_attributes_require_verification" {
  description = "Attributes that require verification before update"
  type        = list(string)
  default     = ["email"]
}

variable "cognito_verification_email_option" {
  description = "Verification email option (CONFIRM_WITH_LINK or CONFIRM_WITH_CODE)"
  type        = string
  default     = "CONFIRM_WITH_CODE"

  validation {
    condition     = contains(["CONFIRM_WITH_LINK", "CONFIRM_WITH_CODE"], var.cognito_verification_email_option)
    error_message = "Verification email option must be CONFIRM_WITH_LINK or CONFIRM_WITH_CODE."
  }
}

variable "cognito_verification_email_subject" {
  description = "Email subject for verification emails"
  type        = string
  default     = "Your verification code"
}

variable "cognito_verification_email_message" {
  description = "Email message for verification emails. Must contain {####} placeholder."
  type        = string
  default     = "Your verification code is {####}."
}

variable "cognito_verification_email_subject_by_link" {
  description = "Email subject for verification link emails"
  type        = string
  default     = "Verify your email"
}

variable "cognito_verification_email_message_by_link" {
  description = "Email message for verification link emails. Must contain {##Verify Email##} placeholder."
  type        = string
  default     = "Please click the link below to verify your email address. {##Verify Email##}"
}

#------------------------------------------------------------------------------
# Cognito User Pool Domain Configuration
#------------------------------------------------------------------------------

variable "cognito_custom_domain" {
  description = "Custom domain for Cognito hosted UI (leave empty for default AWS domain)"
  type        = string
  default     = ""
}

variable "cognito_domain_certificate_arn" {
  description = "ACM certificate ARN for custom domain (required if using custom domain)"
  type        = string
  default     = null
}

#------------------------------------------------------------------------------
# Cognito User Pool Client Configuration
#------------------------------------------------------------------------------

variable "cognito_access_token_validity" {
  description = "Access token validity in time units"
  type        = number
  default     = 60
}

variable "cognito_id_token_validity" {
  description = "ID token validity in time units"
  type        = number
  default     = 60
}

variable "cognito_refresh_token_validity" {
  description = "Refresh token validity in time units"
  type        = number
  default     = 30
}

variable "cognito_access_token_validity_units" {
  description = "Time unit for access token validity (seconds, minutes, hours, days)"
  type        = string
  default     = "minutes"

  validation {
    condition     = contains(["seconds", "minutes", "hours", "days"], var.cognito_access_token_validity_units)
    error_message = "Token validity unit must be seconds, minutes, hours, or days."
  }
}

variable "cognito_id_token_validity_units" {
  description = "Time unit for ID token validity (seconds, minutes, hours, days)"
  type        = string
  default     = "minutes"

  validation {
    condition     = contains(["seconds", "minutes", "hours", "days"], var.cognito_id_token_validity_units)
    error_message = "Token validity unit must be seconds, minutes, hours, or days."
  }
}

variable "cognito_refresh_token_validity_units" {
  description = "Time unit for refresh token validity (seconds, minutes, hours, days)"
  type        = string
  default     = "days"

  validation {
    condition     = contains(["seconds", "minutes", "hours", "days"], var.cognito_refresh_token_validity_units)
    error_message = "Token validity unit must be seconds, minutes, hours, or days."
  }
}

variable "cognito_allowed_oauth_flows" {
  description = "Allowed OAuth flows (code, implicit, client_credentials)"
  type        = list(string)
  default     = ["code"]

  validation {
    condition     = alltrue([for flow in var.cognito_allowed_oauth_flows : contains(["code", "implicit", "client_credentials"], flow)])
    error_message = "OAuth flows must be code, implicit, or client_credentials."
  }
}

variable "cognito_allowed_oauth_flows_user_pool_client" {
  description = "Whether OAuth flows are allowed for the user pool client"
  type        = bool
  default     = true
}

variable "cognito_allowed_oauth_scopes" {
  description = "Allowed OAuth scopes"
  type        = list(string)
  default     = ["email", "openid", "profile"]
}

variable "cognito_callback_urls" {
  description = "List of allowed callback URLs for OAuth"
  type        = list(string)
  default     = []
}

variable "cognito_logout_urls" {
  description = "List of allowed logout URLs"
  type        = list(string)
  default     = []
}

variable "cognito_supported_identity_providers" {
  description = "Supported identity providers (COGNITO, Facebook, Google, etc.)"
  type        = list(string)
  default     = ["COGNITO"]
}

variable "cognito_generate_client_secret" {
  description = "Generate a client secret for the app client"
  type        = bool
  default     = true
}

variable "cognito_prevent_user_existence_errors" {
  description = "How to handle user existence errors (LEGACY or ENABLED)"
  type        = string
  default     = "ENABLED"

  validation {
    condition     = contains(["LEGACY", "ENABLED"], var.cognito_prevent_user_existence_errors)
    error_message = "Prevent user existence errors must be LEGACY or ENABLED."
  }
}

variable "cognito_enable_token_revocation" {
  description = "Enable token revocation"
  type        = bool
  default     = true
}

variable "cognito_enable_propagate_user_context" {
  description = "Enable propagation of additional user context data"
  type        = bool
  default     = false
}

variable "cognito_explicit_auth_flows" {
  description = "Explicit authentication flows enabled"
  type        = list(string)
  default = [
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_SRP_AUTH"
  ]
}

variable "cognito_read_attributes" {
  description = "List of user pool attributes the app client can read"
  type        = list(string)
  default     = ["email", "email_verified", "name"]
}

variable "cognito_write_attributes" {
  description = "List of user pool attributes the app client can write"
  type        = list(string)
  default     = ["email", "name"]
}

#------------------------------------------------------------------------------
# Cognito Resource Server Configuration
#------------------------------------------------------------------------------

variable "cognito_resource_server_identifier" {
  description = "Identifier for the resource server (defaults to route53_zone_name)"
  type        = string
  default     = ""
}

variable "cognito_resource_server_scopes" {
  description = "List of scopes for the resource server"
  type = list(object({
    name        = string
    description = string
  }))
  default = []
}

#------------------------------------------------------------------------------
# Cognito Identity Pool Configuration
#------------------------------------------------------------------------------

variable "enable_cognito_identity_pool" {
  description = "Enable Cognito Identity Pool for federated identities"
  type        = bool
  default     = false
}

variable "cognito_allow_unauthenticated_identities" {
  description = "Allow unauthenticated identities in the identity pool"
  type        = bool
  default     = false
}

variable "cognito_allow_classic_flow" {
  description = "Allow classic (basic) authentication flow"
  type        = bool
  default     = false
}

variable "cognito_server_side_token_check" {
  description = "Enable server-side token validation"
  type        = bool
  default     = true
}

################################################################################
# Region Configuration
################################################################################

variable "aws_allowed_regions" {
  description = "List of AWS regions allowed for resource deployment"
  type        = list(string)
  default     = ["eu-west-2", "us-east-1"]
}
