################################################################################
# Variables - Network Module
################################################################################

#------------------------------------------------------------------------------
# Required Variables
#------------------------------------------------------------------------------

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
  description = "Project name used for resource naming"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment name (e.g., mgmt, dev, staging, prod)"
  type        = string

  # validation {
  #   condition     = contains(["mgmt", "dev", "staging", "prod"], var.environment)
  #   error_message = "Environment must be one of: mgmt, dev, staging, prod."
  # }
}

#------------------------------------------------------------------------------
# VPC Configuration
#------------------------------------------------------------------------------

variable "vpc_cidr" {
  description = "CIDR block for the VPC. Recommended /16 for full subnet allocation."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid CIDR block."
  }
}

variable "az_count" {
  description = "Number of Availability Zones to use. Use 1 for cost-optimised non-production (single NAT GW / single firewall endpoint), 2-3 for high availability."
  type        = number
  default     = 3

  validation {
    condition     = var.az_count >= 1 && var.az_count <= 3
    error_message = "AZ count must be between 1 and 3."
  }
}

variable "enable_ipv6" {
  description = "Enable IPv6 CIDR block assignment for the VPC (dual-stack)"
  type        = bool
  default     = false
}

#------------------------------------------------------------------------------
# NAT Gateway Configuration
#------------------------------------------------------------------------------
# NAT Gateway count is controlled by az_count. Set az_count = 1 for single NAT (cost saving),
# or az_count = 2/3 for per-AZ NAT gateways (high availability).

# #------------------------------------------------------------------------------
# # VPC Flow Logs Configuration
# #------------------------------------------------------------------------------

# variable "flow_logs_retention_days" {
#   description = "Number of days to retain VPC Flow Logs in CloudWatch"
#   type        = number
#   default     = 90

#   validation {
#     condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.flow_logs_retention_days)
#     error_message = "Flow logs retention must be a valid CloudWatch Logs retention period."
#   }
# }

#------------------------------------------------------------------------------
# VPC Endpoints Configuration
#------------------------------------------------------------------------------

variable "enable_interface_endpoints" {
  description = "Enable VPC Interface Endpoints for AWS services (incurs costs)"
  type        = bool
  default     = true
}

variable "interface_endpoints" {
  description = "List of AWS services to create Interface VPC Endpoints for"
  type        = list(string)
  default = [
    # Required: Lambda reads secrets (NHS Login key, supplier credentials) from within the VPC
    "secretsmanager",
    # Required: Lambda writes CloudWatch Logs directly via the Logs API from within the VPC
    "logs",
    # Required: order-result-lambda sends to SQS; order-router-lambda reads from SQS
    "sqs",
    # Required: Lambda decrypts KMS-encrypted secrets
    "kms",
    # Required: Lambda credential refresh inside the VPC - avoids NAT gateway for STS token calls
    "sts",
    # NOT included - removed as unnecessary:
    # "lambda"      - API Gateway/SQS invoke Lambda via Lambda service (not VPC network); nothing inside VPC calls Lambda invoke API
    # "execute-api" - API Gateway is REGIONAL (public); no in-VPC clients call the API GW URL
    # "monitoring"  - No custom PutMetricData calls; Lambda auto-metrics go through the Lambda service
    # "ecr.api"     - Lambdas use ZIP packages (not container images); ECR is not accessed at runtime
    # "ecr.dkr"     - Same as above
  ]
}

#------------------------------------------------------------------------------
# Security Group Flags
#------------------------------------------------------------------------------

variable "create_db_subnet_group" {
  description = "Create a DB subnet group for RDS"
  type        = bool
  default     = true
}

variable "create_lambda_rds_sg" {
  description = "Create a dedicated security group for Lambda to RDS access"
  type        = bool
  default     = true
}

#------------------------------------------------------------------------------
# Network Firewall & Egress Filtering
#------------------------------------------------------------------------------

variable "enable_network_firewall" {
  description = "Enable AWS Network Firewall for egress filtering and deep packet inspection"
  type        = bool
  default     = false
}

variable "firewall_logs_retention_days" {
  description = "Number of days to retain Network Firewall logs in CloudWatch"
  type        = number
  default     = 90

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.firewall_logs_retention_days)
    error_message = "Firewall logs retention must be a valid CloudWatch Logs retention period."
  }
}

variable "enable_firewall_flow_logs" {
  description = "Enable FLOW log type for Network Firewall. FLOW logs record every packet and can be very high volume (10-100x ALERT logs). Disable for non-production environments to reduce CloudWatch ingestion costs."
  type        = bool
  default     = true
}

variable "firewall_default_deny" {
  description = "Enable default deny rule - drops all traffic not explicitly allowed. CAUTION: Ensure all required destinations are in allowed lists before enabling."
  type        = bool
  default     = true
}

variable "firewall_delete_protection" {
  description = "Enable deletion protection for the Network Firewall. Set to true in production to prevent accidental deletion."
  type        = bool
  default     = false
}

variable "firewall_policy_change_protection" {
  description = "Enable firewall policy change protection. Set to true in production to prevent accidental policy changes."
  type        = bool
  default     = false
}

variable "firewall_subnet_change_protection" {
  description = "Enable subnet change protection for the Network Firewall. Set to true in production to prevent accidental subnet changes."
  type        = bool
  default     = false
}

variable "firewall_rule_group_capacities" {
  description = "Capacity units for each Network Firewall rule group. Capacity CANNOT be changed after creation (requires rule group recreation). Set values higher than your expected rule count to allow headroom for growth."
  type = object({
    aws_services  = optional(number, 50)
    egress_ip     = optional(number, 100)
    egress_domain = optional(number, 100)
    ingress_ip    = optional(number, 100)
    drop_all      = optional(number, 10)
  })
  default = {}

  validation {
    condition = alltrue([
      for k, v in var.firewall_rule_group_capacities :
      v != null && v >= 1 && v <= 30000
    ])
    error_message = "Each capacity value must be between 1 and 30000 and cannot be null."
  }
}

variable "firewall_alert_sns_topic_arn" {
  description = "ARN of the SNS topic for Network Firewall CloudWatch alarm notifications. If empty, alarms are created without actions."
  type        = string
  default     = ""
}

variable "allowed_egress_ips" {
  description = "List of allowed egress IP addresses with port and protocol. These IPs will be permitted through the firewall."
  type = list(object({
    ip          = string # IP address in CIDR notation (e.g., "203.0.113.10/32" for single IP)
    port        = string # Port number or "ANY"
    protocol    = string # Protocol: TCP, UDP, or IP
    description = string # Description for documentation
  }))
  default = []

  validation {
    condition = alltrue([
      for rule in var.allowed_egress_ips :
      can(regex("^(?i)(tcp|udp|ip)$", rule.protocol))
    ])
    error_message = "Protocol must be TCP, UDP, or IP (case-insensitive)."
  }

  validation {
    condition = alltrue([
      for rule in var.allowed_egress_ips :
      rule.port == "ANY" || (can(regex("^[0-9]+$", rule.port)) && tonumber(rule.port) >= 1 && tonumber(rule.port) <= 65535)
    ])
    error_message = "Port must be 'ANY' or a valid port number (1-65535)."
  }

  validation {
    condition = alltrue([
      for rule in var.allowed_egress_ips :
      can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+/[0-9]+$", rule.ip)) && can(cidrhost(rule.ip, 0))
    ])
    error_message = "IP must be a valid IPv4 CIDR block. Use /32 for single IPs (e.g., '10.0.0.1/32') or specify a range (e.g., '192.168.0.0/24')."
  }

  validation {
    condition = alltrue([
      for rule in var.allowed_egress_ips :
      can(regex("^[^\";\n\r\\\\]*$", rule.description))
    ])
    error_message = "Descriptions cannot contain quotes (\"), semicolons (;), newlines, or backslashes (\\) as they break Suricata rule syntax."
  }


  # Example:
  # allowed_egress_ips = [
  #   {
  #     ip          = "203.0.113.10/32"
  #     port        = "443"
  #     protocol    = "TCP"
  #     description = "External API server"
  #   },
  #   {
  #     ip          = "198.51.100.0/24"
  #     port        = "ANY"
  #     protocol    = "TCP"
  #     description = "Partner network"
  #   }
  # ]
}

variable "allowed_ingress_ips" {
  description = "List of allowed ingress IP addresses with port and protocol. These IPs will be permitted through the firewall for inbound traffic."
  type = list(object({
    ip          = string # IP address in CIDR notation (e.g., "203.0.113.10/32" for single IP)
    port        = string # Port number or "ANY"
    protocol    = string # Protocol: TCP, UDP, or IP
    description = string # Description for documentation
  }))
  default = []

  validation {
    condition = alltrue([
      for rule in var.allowed_ingress_ips :
      can(regex("^(?i)(tcp|udp|ip)$", rule.protocol))
    ])
    error_message = "Protocol must be TCP, UDP, or IP (case-insensitive)."
  }

  validation {
    condition = alltrue([
      for rule in var.allowed_ingress_ips :
      rule.port == "ANY" || (can(regex("^[0-9]+$", rule.port)) && tonumber(rule.port) >= 1 && tonumber(rule.port) <= 65535)
    ])
    error_message = "Port must be 'ANY' or a valid port number (1-65535)."
  }

  validation {
    condition = alltrue([
      for rule in var.allowed_ingress_ips :
      can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+/[0-9]+$", rule.ip)) && can(cidrhost(rule.ip, 0))
    ])
    error_message = "IP must be a valid IPv4 CIDR block. Use /32 for single IPs (e.g., '10.0.0.1/32') or specify a range (e.g., '192.168.0.0/24')."
  }

  validation {
    condition = alltrue([
      for rule in var.allowed_ingress_ips :
      can(regex("^[^\";\n\r\\\\]*$", rule.description))
    ])
    error_message = "Descriptions cannot contain quotes (\"), semicolons (;), newlines, or backslashes (\\) as they break Suricata rule syntax."
  }

  # Example:
  # allowed_ingress_ips = [
  #   {
  #     ip          = "203.0.113.10/32"
  #     port        = "443"
  #     protocol    = "TCP"
  #     description = "External monitoring service"
  #   }
  # ]
}

variable "allowed_egress_domains" {
  description = "List of allowed egress domains (for HTTPS/TLS traffic). Supports wildcards like '.example.com'."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for d in var.allowed_egress_domains :
      can(regex("^\\.?(?:[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\\.)+[a-zA-Z]{2,}$", d))
    ])
    error_message = "Each domain must be a valid domain name (e.g., 'api.example.com') or wildcard (e.g., '.example.com')."
  }

  # Example:
  # allowed_egress_domains = [
  #   ".github.com",
  #   ".githubusercontent.com",
  #   "api.stripe.com",
  #   ".nhs.uk",
  #   ".gov.uk"
  # ]
}

#------------------------------------------------------------------------------
# Tags
#------------------------------------------------------------------------------

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

#------------------------------------------------------------------------------
# Route 53 Configuration
#------------------------------------------------------------------------------

variable "route53_zone_name" {
  description = "The domain name for the Route 53 hosted zone"
  type        = string
  default     = "hometest.service.nhs.uk"
}

variable "create_private_hosted_zone" {
  description = "Create a private hosted zone associated with the VPC for internal DNS resolution"
  type        = bool
  default     = false
}

variable "private_zone_name" {
  description = "The domain name for the private hosted zone (defaults to route53_zone_name if not specified)"
  type        = string
  default     = ""
}

variable "enable_dnssec" {
  description = "Enable DNSSEC signing for the hosted zone (recommended for security)"
  type        = bool
  default     = false
}

variable "create_health_check" {
  description = "Create a Route 53 health check for the domain"
  type        = bool
  default     = false
}

variable "health_check_fqdn" {
  description = "The FQDN to health check (defaults to route53_zone_name if not specified)"
  type        = string
  default     = ""
}

variable "health_check_port" {
  description = "The port for the health check"
  type        = number
  default     = 443
}

variable "health_check_type" {
  description = "The type of health check (HTTP, HTTPS, HTTP_STR_MATCH, HTTPS_STR_MATCH, TCP)"
  type        = string
  default     = "HTTPS"

  validation {
    condition     = contains(["HTTP", "HTTPS", "HTTP_STR_MATCH", "HTTPS_STR_MATCH", "TCP"], var.health_check_type)
    error_message = "Health check type must be one of: HTTP, HTTPS, HTTP_STR_MATCH, HTTPS_STR_MATCH, TCP."
  }
}

variable "health_check_path" {
  description = "The path for HTTP/HTTPS health checks"
  type        = string
  default     = "/health"
}

variable "health_check_failure_threshold" {
  description = "The number of consecutive health check failures required before considering the endpoint unhealthy"
  type        = number
  default     = 3
}

variable "health_check_request_interval" {
  description = "The number of seconds between health checks (10 or 30)"
  type        = number
  default     = 30

  validation {
    condition     = contains([10, 30], var.health_check_request_interval)
    error_message = "Health check request interval must be 10 or 30 seconds."
  }
}

#------------------------------------------------------------------------------
# DNS Query Logging Configuration
#------------------------------------------------------------------------------

variable "enable_dns_query_logging" {
  description = "Enable DNS query logging for Route 53 with near real-time delivery to S3"
  type        = bool
  default     = true
}

variable "dns_query_logs_retention_days" {
  description = "Number of days to retain DNS query logs in S3 before expiration"
  type        = number
  default     = 90
}

variable "dns_query_logs_cloudwatch_retention_days" {
  description = "Number of days to retain DNS query logs in CloudWatch (before S3 delivery)"
  type        = number
  default     = 7
}

variable "dns_query_logs_buffer_size" {
  description = "Buffer size in MB for Kinesis Firehose (1-128 MB). Smaller = more real-time"
  type        = number
  default     = 5

  validation {
    condition     = var.dns_query_logs_buffer_size >= 1 && var.dns_query_logs_buffer_size <= 128
    error_message = "Buffer size must be between 1 and 128 MB."
  }
}

variable "dns_query_logs_buffer_interval" {
  description = "Buffer interval in seconds for Kinesis Firehose (60-900 seconds). Smaller = more real-time"
  type        = number
  default     = 60

  validation {
    condition     = var.dns_query_logs_buffer_interval >= 60 && var.dns_query_logs_buffer_interval <= 900
    error_message = "Buffer interval must be between 60 and 900 seconds."
  }
}

################################################################################
# Region Configuration
################################################################################

variable "aws_allowed_regions" {
  description = "List of AWS regions allowed for resource deployment"
  type        = list(string)
  default     = ["eu-west-2", "us-east-1"]
}

################################################################################
# Encryption Configuration
################################################################################

variable "logs_kms_key_arn" {
  description = "ARN of the KMS key for logs encryption (from bootstrap module)"
  type        = string
}
