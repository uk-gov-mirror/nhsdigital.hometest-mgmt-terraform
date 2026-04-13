################################################################################
# Security Groups for Lambda Functions
#
# NOTE: All rules use standalone aws_vpc_security_group_*_rule resources
# instead of inline egress/ingress blocks. This allows other modules
# (e.g., hometest-app/wiremock.tf) to safely add rules to these SGs
# without the network module removing them on next apply.
################################################################################

resource "aws_security_group" "lambda" {
  name        = "${local.resource_prefix}-lambda-sg"
  description = "Security group for Lambda functions in VPC"
  vpc_id      = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-lambda-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_egress_rule" "lambda_https" {
  security_group_id = aws_security_group.lambda.id
  description       = "HTTPS outbound for AWS API calls"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-lambda-https-egress"
  })
}

resource "aws_vpc_security_group_egress_rule" "lambda_dns_udp" {
  security_group_id = aws_security_group.lambda.id
  description       = "DNS resolution"
  from_port         = 53
  to_port           = 53
  ip_protocol       = "udp"
  cidr_ipv4         = var.vpc_cidr

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-lambda-dns-udp-egress"
  })
}

resource "aws_vpc_security_group_egress_rule" "lambda_dns_tcp" {
  security_group_id = aws_security_group.lambda.id
  description       = "DNS resolution TCP"
  from_port         = 53
  to_port           = 53
  ip_protocol       = "tcp"
  cidr_ipv4         = var.vpc_cidr

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-lambda-dns-tcp-egress"
  })
}

################################################################################
# Security Group for Lambda to RDS access
################################################################################

resource "aws_security_group" "lambda_rds" {
  count = var.create_lambda_rds_sg ? 1 : 0

  name        = "${local.resource_prefix}-lambda-rds-sg"
  description = "Security group for Lambda functions accessing RDS"
  vpc_id      = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-lambda-rds-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_egress_rule" "lambda_rds_postgres" {
  for_each = var.create_lambda_rds_sg ? toset(local.data_subnets) : toset([])

  security_group_id = aws_security_group.lambda_rds[0].id
  description       = "PostgreSQL to RDS"
  from_port         = 5432
  to_port           = 5432
  ip_protocol       = "tcp"
  cidr_ipv4         = each.value

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-lambda-rds-postgres-egress"
  })
}

resource "aws_vpc_security_group_egress_rule" "lambda_rds_https" {
  count = var.create_lambda_rds_sg ? 1 : 0

  security_group_id = aws_security_group.lambda_rds[0].id
  description       = "HTTPS for AWS API calls"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  # trivy:ignore:AVD-AWS-0104
  cidr_ipv4 = "0.0.0.0/0"

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-lambda-rds-https-egress"
  })
}

################################################################################
# Security Group for RDS/Database
################################################################################

resource "aws_security_group" "rds" {
  count = var.create_rds_sg ? 1 : 0

  name        = "${local.resource_prefix}-rds-sg"
  description = "Security group for RDS databases"
  vpc_id      = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-rds-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_lambda" {
  count = var.create_rds_sg ? 1 : 0

  security_group_id            = aws_security_group.rds[0].id
  description                  = "PostgreSQL from Lambda"
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.lambda.id

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-rds-from-lambda-ingress"
  })
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_lambda_rds" {
  count = var.create_rds_sg && var.create_lambda_rds_sg ? 1 : 0

  security_group_id            = aws_security_group.rds[0].id
  description                  = "PostgreSQL from Lambda RDS SG"
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.lambda_rds[0].id

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-rds-from-lambda-rds-ingress"
  })
}

# ElastiCache not used in this deployment - only RDS PostgreSQL, Lambda, API Gateway, WAF, SQS, S3
