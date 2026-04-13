################################################################################
# Outputs - Network Module
################################################################################

#------------------------------------------------------------------------------
# VPC Outputs
#------------------------------------------------------------------------------

output "vpc_id" {
  description = "The ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr_block" {
  description = "The CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "vpc_arn" {
  description = "The ARN of the VPC"
  value       = aws_vpc.main.arn
}

#------------------------------------------------------------------------------
# Subnet Outputs
#------------------------------------------------------------------------------

output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = aws_subnet.public[*].id
}

output "public_subnet_arns" {
  description = "List of public subnet ARNs"
  value       = aws_subnet.public[*].arn
}

output "public_subnet_cidrs" {
  description = "List of public subnet CIDR blocks"
  value       = aws_subnet.public[*].cidr_block
}

output "firewall_subnet_arns" {
  description = "List of firewall subnet ARNs"
  value       = aws_subnet.firewall[*].arn
}

output "firewall_subnet_cidrs" {
  description = "List of firewall subnet CIDR blocks"
  value       = aws_subnet.firewall[*].cidr_block
}

output "private_subnet_ids" {
  description = "List of private subnet IDs (use for Lambda VPC configuration)"
  value       = aws_subnet.private[*].id
}

output "private_subnet_arns" {
  description = "List of private subnet ARNs"
  value       = aws_subnet.private[*].arn
}

output "private_subnet_cidrs" {
  description = "List of private subnet CIDR blocks"
  value       = aws_subnet.private[*].cidr_block
}

output "data_subnet_ids" {
  description = "List of data/database subnet IDs"
  value       = aws_subnet.data[*].id
}

output "data_subnet_arns" {
  description = "List of data/database subnet ARNs"
  value       = aws_subnet.data[*].arn
}

output "data_subnet_cidrs" {
  description = "List of data/database subnet CIDR blocks"
  value       = aws_subnet.data[*].cidr_block
}

#------------------------------------------------------------------------------
# Availability Zones
#------------------------------------------------------------------------------

output "availability_zones" {
  description = "List of availability zones used"
  value       = local.azs
}

#------------------------------------------------------------------------------
# NAT Gateway Outputs
#------------------------------------------------------------------------------

output "nat_gateway_ids" {
  description = "List of NAT Gateway IDs"
  value       = aws_nat_gateway.main[*].id
}

output "nat_gateway_public_ips" {
  description = "List of NAT Gateway public IP addresses"
  value       = aws_eip.nat[*].public_ip
}

#------------------------------------------------------------------------------
# Route Table Outputs
#------------------------------------------------------------------------------

output "public_route_table_id" {
  description = "ID of the public route table"
  value       = aws_route_table.public.id
}

output "private_route_table_ids" {
  description = "List of private route table IDs"
  value       = aws_route_table.private[*].id
}

output "data_route_table_id" {
  description = "ID of the data route table"
  value       = aws_route_table.data.id
}

#------------------------------------------------------------------------------
# Security Group Outputs
#------------------------------------------------------------------------------

output "lambda_security_group_id" {
  description = "Security group ID for Lambda functions (use for Lambda VPC configuration)"
  value       = aws_security_group.lambda.id
}

output "lambda_security_group_arn" {
  description = "Security group ARN for Lambda functions"
  value       = aws_security_group.lambda.arn
}

output "lambda_rds_security_group_id" {
  description = "Security group ID for Lambda functions accessing RDS"
  value       = var.create_lambda_rds_sg ? aws_security_group.lambda_rds[0].id : null
}

# output "elasticache_security_group_id" {
#   description = "Security group ID for ElastiCache"
#   value       = var.create_elasticache_sg ? aws_security_group.elasticache[0].id : null
# }

output "vpc_endpoints_security_group_id" {
  description = "Security group ID for VPC Interface Endpoints"
  value       = aws_security_group.vpc_endpoints.id
}

#------------------------------------------------------------------------------
# VPC Endpoint Outputs
#------------------------------------------------------------------------------

output "s3_vpc_endpoint_id" {
  description = "ID of the S3 Gateway VPC Endpoint"
  value       = aws_vpc_endpoint.s3.id
}

# output "dynamodb_vpc_endpoint_id" {
#   description = "ID of the DynamoDB Gateway VPC Endpoint"
#   value       = aws_vpc_endpoint.dynamodb.id
# }

output "interface_vpc_endpoint_ids" {
  description = "Map of Interface VPC Endpoint IDs"
  value       = { for k, v in aws_vpc_endpoint.interface_endpoints : k => v.id }
}

#------------------------------------------------------------------------------
# DB Subnet Group Outputs
#------------------------------------------------------------------------------

output "db_subnet_group_name" {
  description = "Name of the DB subnet group"
  value       = var.create_db_subnet_group ? aws_db_subnet_group.main[0].name : null
}

output "db_subnet_group_arn" {
  description = "ARN of the DB subnet group"
  value       = var.create_db_subnet_group ? aws_db_subnet_group.main[0].arn : null
}

#------------------------------------------------------------------------------
# VPC Flow Logs Outputs
#------------------------------------------------------------------------------

output "vpc_flow_log_id" {
  description = "ID of the VPC Flow Log"
  value       = aws_flow_log.main.id
}

output "vpc_flow_log_group_arn" {
  description = "ARN of the CloudWatch Log Group for VPC Flow Logs"
  value       = data.aws_cloudwatch_log_group.vpc_flow_logs.arn
}

output "vpc_flow_log_kms_key_arn" {
  description = "ARN of the KMS key used to encrypt VPC Flow Logs"
  value       = var.logs_kms_key_arn
}

#------------------------------------------------------------------------------
# Lambda VPC Configuration (convenience output)
#------------------------------------------------------------------------------

output "lambda_vpc_config" {
  description = "VPC configuration for Lambda functions (ready to use)"
  value = {
    subnet_ids         = aws_subnet.private[*].id
    security_group_ids = [aws_security_group.lambda.id]
  }
}

#------------------------------------------------------------------------------
# Network ACL Outputs
#------------------------------------------------------------------------------

output "private_nacl_id" {
  description = "ID of the private subnet Network ACL"
  value       = aws_network_acl.private.id
}

output "data_nacl_id" {
  description = "ID of the data subnet Network ACL"
  value       = aws_network_acl.data.id
}

#------------------------------------------------------------------------------
# Network Firewall Outputs
#------------------------------------------------------------------------------

output "network_firewall_enabled" {
  description = "Whether Network Firewall is enabled"
  value       = var.enable_network_firewall
}

output "network_firewall_id" {
  description = "ID of the Network Firewall"
  value       = var.enable_network_firewall ? aws_networkfirewall_firewall.main[0].id : null
}

output "network_firewall_arn" {
  description = "ARN of the Network Firewall"
  value       = var.enable_network_firewall ? aws_networkfirewall_firewall.main[0].arn : null
}

output "network_firewall_policy_arn" {
  description = "ARN of the Network Firewall Policy"
  value       = var.enable_network_firewall ? aws_networkfirewall_firewall_policy.main[0].arn : null
}

output "network_firewall_endpoint_ids" {
  description = "Map of AZ to Network Firewall endpoint IDs"
  value       = var.enable_network_firewall ? local.firewall_endpoint_ids : {}
}

output "firewall_subnet_ids" {
  description = "List of firewall subnet IDs"
  value       = var.enable_network_firewall ? aws_subnet.firewall[*].id : []
}

output "network_firewall_log_group_arn" {
  description = "ARN of the CloudWatch Log Group for Network Firewall logs"
  value       = var.enable_network_firewall ? aws_cloudwatch_log_group.network_firewall[0].arn : null
}

output "network_firewall_kms_key_arn" {
  description = "ARN of the KMS key used to encrypt Network Firewall logs"
  value       = var.enable_network_firewall ? aws_kms_key.network_firewall[0].arn : null
}

output "egress_filtering_config" {
  description = "Summary of egress filtering configuration"
  value = var.enable_network_firewall ? {
    firewall_enabled  = true
    default_deny      = var.firewall_default_deny
    allowed_ips_count = length(var.allowed_egress_ips)
    allowed_domains   = var.allowed_egress_domains
    } : {
    firewall_enabled  = false
    default_deny      = false
    allowed_ips_count = 0
    allowed_domains   = []
  }
}

#------------------------------------------------------------------------------
# Route 53 Outputs
#------------------------------------------------------------------------------

output "route53_zone_id" {
  description = "The ID of the Route 53 hosted zone"
  value       = aws_route53_zone.main.zone_id
}

output "route53_zone_arn" {
  description = "The ARN of the Route 53 hosted zone"
  value       = aws_route53_zone.main.arn
}

output "route53_zone_name" {
  description = "The name of the Route 53 hosted zone"
  value       = aws_route53_zone.main.name
}

output "route53_name_servers" {
  description = "The name servers for the Route 53 hosted zone (delegate to these from parent domain)"
  value       = aws_route53_zone.main.name_servers
}

output "route53_private_zone_id" {
  description = "The ID of the private Route 53 hosted zone"
  value       = var.create_private_hosted_zone ? aws_route53_zone.private[0].zone_id : null
}

output "route53_private_zone_arn" {
  description = "The ARN of the private Route 53 hosted zone"
  value       = var.create_private_hosted_zone ? aws_route53_zone.private[0].arn : null
}

output "route53_health_check_id" {
  description = "The ID of the Route 53 health check"
  value       = var.create_health_check ? aws_route53_health_check.main[0].id : null
}

output "dnssec_enabled" {
  description = "Whether DNSSEC is enabled for the hosted zone"
  value       = var.enable_dnssec
}

output "dnssec_kms_key_arn" {
  description = "The ARN of the KMS key used for DNSSEC signing"
  value       = var.enable_dnssec ? aws_kms_key.dnssec[0].arn : null
}

#------------------------------------------------------------------------------
# DNS Query Logging Outputs
#------------------------------------------------------------------------------

output "dns_query_logging_enabled" {
  description = "Whether DNS query logging is enabled"
  value       = var.enable_dns_query_logging
}

output "dns_query_logs_s3_bucket_id" {
  description = "The ID of the S3 bucket for DNS query logs"
  value       = var.enable_dns_query_logging ? aws_s3_bucket.dns_query_logs[0].id : null
}

output "dns_query_logs_s3_bucket_arn" {
  description = "The ARN of the S3 bucket for DNS query logs"
  value       = var.enable_dns_query_logging ? aws_s3_bucket.dns_query_logs[0].arn : null
}

output "dns_query_logs_cloudwatch_log_group_arn" {
  description = "The ARN of the CloudWatch Log Group for DNS query logs (us-east-1)"
  value       = var.enable_dns_query_logging ? aws_cloudwatch_log_group.dns_query_logs[0].arn : null
}

output "dns_query_logs_firehose_arn" {
  description = "The ARN of the Kinesis Firehose delivery stream for DNS query logs"
  value       = var.enable_dns_query_logging ? aws_kinesis_firehose_delivery_stream.dns_query_logs[0].arn : null
}

output "dns_query_logs_kms_key_arn" {
  description = "The ARN of the KMS key used to encrypt DNS query logs"
  value       = var.enable_dns_query_logging ? var.logs_kms_key_arn : null
}

output "dns_query_log_config_id" {
  description = "The ID of the Route 53 query log configuration"
  value       = var.enable_dns_query_logging ? aws_route53_query_log.main[0].id : null
}

output "private_dns_query_log_config_id" {
  description = "The ID of the Route 53 Resolver query log configuration for private zones"
  value       = var.enable_dns_query_logging && var.create_private_hosted_zone ? aws_route53_resolver_query_log_config.private[0].id : null
}

output "dns_query_logging_config" {
  description = "Summary of DNS query logging configuration"
  value = var.enable_dns_query_logging ? {
    enabled                 = true
    s3_bucket               = aws_s3_bucket.dns_query_logs[0].id
    firehose_stream         = aws_kinesis_firehose_delivery_stream.dns_query_logs[0].name
    buffer_interval_seconds = var.dns_query_logs_buffer_interval
    buffer_size_mb          = var.dns_query_logs_buffer_size
    retention_days          = var.dns_query_logs_retention_days
    } : {
    enabled                 = false
    s3_bucket               = null
    firehose_stream         = null
    buffer_interval_seconds = null
    buffer_size_mb          = null
    retention_days          = null
  }
}
