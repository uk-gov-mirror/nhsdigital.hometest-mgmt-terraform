################################################################################
# WireMock ECS Service (Fargate)
#
# Deploys the official WireMock Docker image on ECS Fargate for:
# - Stubbing 3rd-party APIs in dev environments
# - Providing a mock backend for Playwright end-to-end tests
#
# Uses terraform-aws-modules/ecs/aws//modules/service for the ECS service
# and terraform-aws-modules/alb/aws for the internet-facing ALB.
#
# Exposure model (mirrors Lambda/API Gateway):
# - Internet-facing ALB in public subnets (protected by network firewall)
# - Regional WAF attached to the ALB (same rules as API Gateway)
# - HTTPS via shared wildcard ACM certificate
# - Route53 alias: wiremock-<env>.<account>.hometest.service.nhs.uk
#
# Cost optimisations (dev-only workloads):
# - ARM64 (Graviton) — ~20% cheaper than x86_64
# - Fargate Spot capacity provider — up to 70% savings
# - Minimal CPU/memory (256 CPU / 512 MiB)
# - Single task (desired_count = 1)
#
# Service is only created when var.enable_wiremock = true.
# Service discovery enables internal access at:
#   wiremock-<env>.ecs.<prefix>.local:8080
################################################################################

locals {
  wiremock_name           = "${local.resource_prefix}-wiremock"
  wiremock_container_port = 8080
  wiremock_domain         = var.enable_wiremock && var.wiremock_domain_name != null ? var.wiremock_domain_name : null
}

################################################################################
# Data source — VPC CIDR for security group rules
################################################################################

data "aws_vpc" "selected" {
  count = var.enable_wiremock ? 1 : 0
  id    = var.vpc_id
}

################################################################################
# CloudWatch Log Group (created outside the module for KMS encryption control)
################################################################################

resource "aws_cloudwatch_log_group" "wiremock" {
  count = var.enable_wiremock ? 1 : 0

  name              = "/ecs/${local.wiremock_name}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn

  tags = local.common_tags
}

################################################################################
# Internet-facing ALB — terraform-aws-modules/alb/aws
# https://github.com/terraform-aws-modules/terraform-aws-alb/releases
#
# Placed in PUBLIC subnets so it gets a public IP and is reachable from the
# internet. The AWS Network Firewall (if enabled) inspects all ingress/egress
# traffic on the public subnets automatically via VPC route tables.
################################################################################

module "wiremock_alb" {
  count = var.enable_wiremock ? 1 : 0

  #checkov:skip=CKV_TF_1:Using a commit hash for module from the Terraform registry is not applicable
  source  = "terraform-aws-modules/alb/aws"
  version = "~> 9.16.0"

  name     = "${local.wiremock_name}-alb"
  internal = false # Internet-facing — same as API Gateway exposure model

  vpc_id  = var.vpc_id
  subnets = var.wiremock_public_subnet_ids # Public subnets (protected by network firewall)

  enable_deletion_protection = false
  drop_invalid_header_fields = true

  # Security group — HTTPS from internet (WAF provides L7 protection)
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
    to_targets = {
      from_port                    = local.wiremock_container_port
      to_port                      = local.wiremock_container_port
      ip_protocol                  = "tcp"
      referenced_security_group_id = module.wiremock_service[0].security_group_id
      description                  = "To WireMock ECS tasks"
    }
  }

  listeners = {
    # HTTPS listener — terminates TLS with shared wildcard certificate
    https = {
      port            = 443
      protocol        = "HTTPS"
      ssl_policy      = "ELBSecurityPolicy-TLS13-1-2-2021-06"
      certificate_arn = var.acm_regional_certificate_arn

      forward = {
        target_group_key = "wiremock"
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

  target_groups = {
    wiremock = {
      name             = "${local.wiremock_name}-tg"
      backend_port     = local.wiremock_container_port
      backend_protocol = "HTTP"
      target_type      = "ip"

      health_check = {
        enabled             = true
        path                = "/__admin/health"
        port                = "traffic-port"
        protocol            = "HTTP"
        healthy_threshold   = 2
        unhealthy_threshold = 3
        timeout             = 5
        interval            = 30
        matcher             = "200"
      }

      # ECS service manages target registration
      create_attachment = false
    }
  }

  tags = local.common_tags
}

################################################################################
# WAF Association — same regional WAF as API Gateway
################################################################################

resource "aws_wafv2_web_acl_association" "wiremock" {
  count = var.enable_wiremock && var.waf_regional_arn != null ? 1 : 0

  resource_arn = module.wiremock_alb[0].arn
  web_acl_arn  = var.waf_regional_arn
}

################################################################################
# Route53 — custom domain for WireMock
# Pattern: wiremock-<env>.<account>.hometest.service.nhs.uk
# Covered by shared wildcard cert *.poc.hometest.service.nhs.uk
################################################################################

resource "aws_route53_record" "wiremock" {
  count = var.enable_wiremock && local.wiremock_domain != null ? 1 : 0

  zone_id = var.route53_zone_id
  name    = local.wiremock_domain
  type    = "A"

  alias {
    name                   = module.wiremock_alb[0].dns_name
    zone_id                = module.wiremock_alb[0].zone_id
    evaluate_target_health = true
  }
}

################################################################################
# Service Discovery
################################################################################

resource "aws_service_discovery_service" "wiremock" {
  count = var.enable_wiremock && var.wiremock_service_discovery_namespace_id != null ? 1 : 0

  name = "wiremock-${var.environment}"

  dns_config {
    namespace_id = var.wiremock_service_discovery_namespace_id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
  }

  tags = local.common_tags
}

################################################################################
# ECS Service — terraform-aws-modules/ecs/aws//modules/service
# https://github.com/terraform-aws-modules/terraform-aws-ecs/releases
#
# Tasks run in PRIVATE subnets — only the ALB is in public subnets.
################################################################################

module "wiremock_service" {
  count = var.enable_wiremock ? 1 : 0

  #checkov:skip=CKV_TF_1:Using a commit hash for module from the Terraform registry is not applicable
  source  = "terraform-aws-modules/ecs/aws//modules/service"
  version = "~> 5.12.0"

  name        = local.wiremock_name
  cluster_arn = var.wiremock_ecs_cluster_arn

  # ---------------------------------------------------------------------------
  # Cost: Fargate Spot + ARM64 Graviton
  # ---------------------------------------------------------------------------
  cpu    = var.wiremock_cpu
  memory = var.wiremock_memory

  runtime_platform = {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }

  capacity_provider_strategy = {
    fargate_spot = {
      capacity_provider = "FARGATE_SPOT"
      weight            = 1
      base              = 1
    }
  }

  desired_count = var.wiremock_desired_count

  # ---------------------------------------------------------------------------
  # Deployment
  # ---------------------------------------------------------------------------
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  deployment_circuit_breaker = {
    enable   = true
    rollback = true
  }

  # ---------------------------------------------------------------------------
  # Container definition
  # ---------------------------------------------------------------------------
  container_definitions = {
    wiremock = {
      image     = "wiremock/wiremock:${var.wiremock_image_tag}"
      essential = true

      command = [
        "--port", tostring(local.wiremock_container_port),
        "--verbose",
        "--global-response-templating",
        "--permitted-system-keys=.*"
      ]

      port_mappings = [{
        containerPort = local.wiremock_container_port
        protocol      = "tcp"
      }]

      readonly_root_filesystem = false # WireMock writes mappings/files to disk

      log_configuration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.wiremock[0].name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "wiremock"
        }
      }

      health_check = {
        command     = ["CMD-SHELL", "wget --spider --quiet http://localhost:${local.wiremock_container_port}/__admin/health || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 15
      }
    }
  }

  # ---------------------------------------------------------------------------
  # IAM — Task Execution Role (pulls image, writes logs)
  # ---------------------------------------------------------------------------
  task_exec_iam_role_name        = "${local.wiremock_name}-exec"
  task_exec_iam_role_description = "ECS task execution role for WireMock — pulls images and writes logs"

  task_exec_iam_statements = {
    kms = {
      effect    = "Allow"
      actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
      resources = [var.kms_key_arn]
    }
  }

  # ---------------------------------------------------------------------------
  # IAM — Task Role (container runtime permissions — minimal for WireMock)
  # ---------------------------------------------------------------------------
  tasks_iam_role_name        = "${local.wiremock_name}-task"
  tasks_iam_role_description = "ECS task role for WireMock — no extra permissions needed"

  tasks_iam_role_statements = {}

  # ---------------------------------------------------------------------------
  # Networking — PRIVATE subnets, no public IP
  # ---------------------------------------------------------------------------
  subnet_ids         = var.wiremock_subnet_ids # Private subnets (tasks don't need internet directly)
  assign_public_ip   = false
  enable_autoscaling = false

  # Security group — ALB + Lambda ingress; HTTPS + DNS egress
  security_group_name        = "${local.wiremock_name}-sg"
  security_group_description = "Security group for WireMock ECS tasks"

  security_group_rules = merge(
    {
      alb_ingress = {
        type                     = "ingress"
        from_port                = local.wiremock_container_port
        to_port                  = local.wiremock_container_port
        protocol                 = "tcp"
        source_security_group_id = module.wiremock_alb[0].security_group_id
        description              = "HTTP from ALB"
      }
      https_egress = {
        type        = "egress"
        from_port   = 443
        to_port     = 443
        protocol    = "tcp"
        cidr_ipv4   = "0.0.0.0/0"
        description = "HTTPS outbound for ECR and CloudWatch"
      }
      dns_udp_egress = {
        type        = "egress"
        from_port   = 53
        to_port     = 53
        protocol    = "udp"
        cidr_ipv4   = data.aws_vpc.selected[0].cidr_block
        description = "DNS (UDP)"
      }
      dns_tcp_egress = {
        type        = "egress"
        from_port   = 53
        to_port     = 53
        protocol    = "tcp"
        cidr_ipv4   = data.aws_vpc.selected[0].cidr_block
        description = "DNS (TCP)"
      }
    },
    # Allow Lambda functions to call WireMock directly (service-to-service)
    { for idx, sg_id in var.lambda_security_group_ids : "lambda_ingress_${idx}" => {
      type                     = "ingress"
      from_port                = local.wiremock_container_port
      to_port                  = local.wiremock_container_port
      protocol                 = "tcp"
      source_security_group_id = sg_id
      description              = "HTTP from Lambda SG ${sg_id}"
    } }
  )

  # ---------------------------------------------------------------------------
  # Load balancer
  # ---------------------------------------------------------------------------
  load_balancer = {
    wiremock = {
      target_group_arn = module.wiremock_alb[0].target_groups["wiremock"].arn
      container_name   = "wiremock"
      container_port   = local.wiremock_container_port
    }
  }

  # ---------------------------------------------------------------------------
  # Service discovery
  # ---------------------------------------------------------------------------
  service_registries = var.wiremock_service_discovery_namespace_id != null ? {
    wiremock = {
      registry_arn = aws_service_discovery_service.wiremock[0].arn
    }
  } : {}

  ignore_task_definition_changes = false

  tags = local.common_tags
}
