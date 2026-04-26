################################################################################
# AWS Network Firewall - Egress Filtering
################################################################################

# Firewall Subnets (dedicated subnets for Network Firewall endpoints)
resource "aws_subnet" "firewall" {
  count = var.enable_network_firewall ? length(local.azs) : 0

  vpc_id            = aws_vpc.main.id
  cidr_block        = local.firewall_subnets[count.index]
  availability_zone = local.azs[count.index]

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-firewall-${local.azs[count.index]}"
    Tier = "firewall"
  })
}

# Route table for firewall subnets
resource "aws_route_table" "firewall" {
  count = var.enable_network_firewall ? length(local.azs) : 0

  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-firewall-rt-${count.index + 1}"
  })
}

# Route from firewall subnet to NAT Gateway (for egress filtering)
resource "aws_route" "firewall_nat" {
  count = var.enable_network_firewall ? length(local.azs) : 0

  route_table_id         = aws_route_table.firewall[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main[count.index].id
}

resource "aws_route_table_association" "firewall" {
  count = var.enable_network_firewall ? length(local.azs) : 0

  subnet_id      = aws_subnet.firewall[count.index].id
  route_table_id = aws_route_table.firewall[count.index].id
}

################################################################################
# Network Firewall Logging
################################################################################

resource "aws_cloudwatch_log_group" "network_firewall" {
  count = var.enable_network_firewall ? 1 : 0

  name              = "/aws/network-firewall/${local.resource_prefix}"
  retention_in_days = var.firewall_logs_retention_days
  kms_key_id        = aws_kms_key.network_firewall[0].arn

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-network-firewall-logs"
  })
}

resource "aws_kms_key" "network_firewall" {
  count = var.enable_network_firewall ? 1 : 0

  description             = "KMS key for Network Firewall logs encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow CloudWatch Logs"
        Effect = "Allow"
        Principal = {
          Service = "logs.${var.aws_region}.amazonaws.com"
        }
        Action = [
          "kms:Encrypt*",
          "kms:Decrypt*",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:Describe*"
        ]
        Resource = "*"
        Condition = {
          ArnLike = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/network-firewall/${local.resource_prefix}"
          }
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-network-firewall-kms"
  })
}

resource "aws_kms_alias" "network_firewall" {
  count = var.enable_network_firewall ? 1 : 0

  name          = "alias/${local.resource_prefix}-network-firewall"
  target_key_id = aws_kms_key.network_firewall[0].key_id
}

################################################################################
# Network Firewall
################################################################################

resource "aws_networkfirewall_firewall" "main" {
  count = var.enable_network_firewall ? 1 : 0

  name                              = "${local.resource_prefix}-network-firewall"
  firewall_policy_arn               = aws_networkfirewall_firewall_policy.main[0].arn
  vpc_id                            = aws_vpc.main.id
  delete_protection                 = true
  firewall_policy_change_protection = true
  subnet_change_protection          = true

  dynamic "subnet_mapping" {
    for_each = aws_subnet.firewall
    content {
      subnet_id = subnet_mapping.value.id
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-network-firewall"
  })
}

resource "aws_networkfirewall_logging_configuration" "main" {
  count = var.enable_network_firewall ? 1 : 0

  firewall_arn = aws_networkfirewall_firewall.main[0].arn

  logging_configuration {
    log_destination_config {
      log_destination = {
        logGroup = aws_cloudwatch_log_group.network_firewall[0].name
      }
      log_destination_type = "CloudWatchLogs"
      log_type             = "ALERT"
    }

    dynamic "log_destination_config" {
      for_each = var.enable_firewall_flow_logs ? [1] : []
      content {
        log_destination = {
          logGroup = aws_cloudwatch_log_group.network_firewall[0].name
        }
        log_destination_type = "CloudWatchLogs"
        log_type             = "FLOW"
      }
    }
  }
}

################################################################################
# Firewall Endpoint IDs for Routing
################################################################################

locals {
  firewall_endpoint_ids = var.enable_network_firewall ? {
    for sync_state in aws_networkfirewall_firewall.main[0].firewall_status[0].sync_states :
    sync_state.availability_zone => sync_state.attachment[0].endpoint_id
  } : {}
}
