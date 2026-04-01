################################################################################
# ECS Cluster (Fargate) - Core Infrastructure
# Shared ECS cluster used by all environments for container workloads.
# Uses terraform-aws-modules/ecs/aws for the cluster and capacity providers.
################################################################################

locals {
  resource_prefix = "${var.project_name}-${var.aws_account_shortname}-${var.environment}"

  common_tags = merge(var.tags, {
    Component = "ecs-cluster"
  })
}

################################################################################
# ECS Cluster via official AWS module
# https://github.com/terraform-aws-modules/terraform-aws-ecs/releases
################################################################################

module "ecs_cluster" {
  #checkov:skip=CKV_TF_1:Using a commit hash for module from the Terraform registry is not applicable
  source  = "terraform-aws-modules/ecs/aws//modules/cluster"
  version = "~> 7.5.0"

  name = "${local.resource_prefix}-ecs"

  # Container Insights for observability
  setting = [{
    name  = "containerInsights"
    value = "enhanced"
  }]

  # ECS Exec audit logging (encrypted)
  configuration = {
    execute_command_configuration = {
      kms_key_id = var.kms_key_arn
      logging    = "OVERRIDE"
      log_configuration = {
        cloud_watch_encryption_enabled = true
        cloud_watch_log_group_name     = aws_cloudwatch_log_group.ecs_exec.name
      }
    }
  }

  # Fargate capacity providers — FARGATE_SPOT as default for cost savings (dev-only workloads)
  # v7: cluster_capacity_providers must be explicitly listed
  cluster_capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy = {
    FARGATE = {
      weight = 0
    }
    FARGATE_SPOT = {
      weight = 1
      base   = 1
    }
  }

  tags = local.common_tags
}

################################################################################
# CloudWatch Log Groups
################################################################################

resource "aws_cloudwatch_log_group" "ecs_exec" {
  name              = "/ecs/${local.resource_prefix}/exec-audit"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn

  tags = local.common_tags
}

################################################################################
# Shared Internet-facing ALB — terraform-aws-modules/alb/aws
# https://github.com/terraform-aws-modules/terraform-aws-alb/releases
#
# Single ALB shared by all ECS services. Each service registers its own
# target group and path-based listener rule.
#
# Placed in PUBLIC subnets (protected by network firewall via VPC route tables).
# Default HTTPS action returns 404 — services add path-based rules on top.
################################################################################

module "ecs_alb" {
  count = var.enable_alb ? 1 : 0

  #checkov:skip=CKV_TF_1:Using a commit hash for module from the Terraform registry is not applicable
  source  = "terraform-aws-modules/alb/aws"
  version = "~> 10.5.0"

  name     = "${local.resource_prefix}-ecs-alb"
  internal = false

  vpc_id  = var.vpc_id
  subnets = var.public_subnet_ids

  enable_deletion_protection = false
  drop_invalid_header_fields = true

  # Security group — HTTPS + HTTP from internet (WAF provides L7 protection)
  security_group_ingress_rules = {
    https_all = {
      from_port   = 443
      to_port     = 443
      ip_protocol = "tcp"
      cidr_ipv4   = "0.0.0.0/0"
      description = "HTTPS from internet"
    }
    http_all = {
      from_port   = 80
      to_port     = 80
      ip_protocol = "tcp"
      cidr_ipv4   = "0.0.0.0/0"
      description = "HTTP from internet (redirected to HTTPS)"
    }
  }
  security_group_egress_rules = {
    all_vpc = {
      ip_protocol = "-1"
      cidr_ipv4   = data.aws_vpc.main[0].cidr_block
      description = "All traffic within VPC (to ECS tasks)"
    }
  }

  listeners = {
    # HTTPS listener — default action returns 404 (services add path-based rules)
    https = {
      port            = 443
      protocol        = "HTTPS"
      ssl_policy      = "ELBSecurityPolicy-TLS13-1-2-2021-06"
      certificate_arn = var.acm_regional_certificate_arn

      fixed_response = {
        content_type = "application/json"
        message_body = "{\"error\":\"not_found\"}"
        status_code  = 404
      }
    }

    # HTTP listener — redirect all HTTP to HTTPS
    http = {
      port     = 80
      protocol = "HTTP"

      redirect = {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  }

  tags = local.common_tags
}

################################################################################
# VPC data source (for ALB egress rule)
################################################################################

data "aws_vpc" "main" {
  count = var.enable_alb ? 1 : 0
  id    = var.vpc_id
}

################################################################################
# WAF Association — same regional WAF as API Gateway
################################################################################

resource "aws_wafv2_web_acl_association" "ecs_alb" {
  count = var.enable_alb && var.waf_regional_arn != null ? 1 : 0

  resource_arn = module.ecs_alb[0].arn
  web_acl_arn  = var.waf_regional_arn
}

################################################################################
# Service Discovery Namespace (Private DNS)
################################################################################

resource "aws_service_discovery_private_dns_namespace" "main" {
  name        = "ecs.${local.resource_prefix}.local"
  description = "Service discovery namespace for ECS services"
  vpc         = var.vpc_id

  tags = local.common_tags
}
