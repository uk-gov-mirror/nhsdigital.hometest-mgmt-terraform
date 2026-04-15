################################################################################
# WireMock ECS Service (Fargate)
#
# Deploys the official WireMock Docker image on ECS Fargate for:
# - Stubbing 3rd-party APIs in dev environments
# - Providing a mock backend for Playwright end-to-end tests
#
# Uses terraform-aws-modules/ecs/aws//modules/service for the ECS service.
# Routes traffic via a path-based listener rule on the shared core ALB.
#
# Exposure model (mirrors Lambda/API Gateway):
# - Shared internet-facing ALB in public subnets (from core ecs module)
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

resource "random_id" "wiremock" {
  count       = var.enable_wiremock ? 1 : 0
  byte_length = 3

  keepers = {
    # Tie the ID to the deployment so it stays stable unless the prefix changes
    resource_prefix = local.resource_prefix
  }
}

locals {
  wiremock_name           = "${local.resource_prefix}-wiremock"
  wiremock_short_uid      = var.enable_wiremock ? "${var.project_name}-${var.aws_account_shortname}-wm-${random_id.wiremock[0].hex}" : "" # ALB/TG names (32 char limit)
  wiremock_container_port = 8080
  wiremock_domain         = var.enable_wiremock && var.wiremock_domain_name != null ? var.wiremock_domain_name : null

  # When bypass_waf is true, WireMock gets its own internet-facing ALB without WAF.
  # When false, it shares the core ALB (which has WAF attached).
  wiremock_use_dedicated_alb = var.enable_wiremock && var.wiremock_bypass_waf

  # Resolve which ALB values to use for listener rules, DNS, and SG references
  wiremock_effective_alb_dns_name          = local.wiremock_use_dedicated_alb ? try(aws_lb.wiremock[0].dns_name, null) : var.wiremock_alb_dns_name
  wiremock_effective_alb_zone_id           = local.wiremock_use_dedicated_alb ? try(aws_lb.wiremock[0].zone_id, null) : var.wiremock_alb_zone_id
  wiremock_effective_https_listener_arn    = local.wiremock_use_dedicated_alb ? try(aws_lb_listener.wiremock_https[0].arn, null) : var.wiremock_alb_https_listener_arn
  wiremock_effective_alb_security_group_id = local.wiremock_use_dedicated_alb ? try(aws_security_group.wiremock_alb[0].id, null) : var.wiremock_alb_security_group_id
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
# Dedicated ALB (no WAF) — created only when wiremock_bypass_waf = true
# Internet-facing ALB in public subnets, with its own security group and
# HTTPS listener. Replaces the shared core ALB for this WireMock instance.
################################################################################

resource "aws_security_group" "wiremock_alb" {
  count = local.wiremock_use_dedicated_alb ? 1 : 0

  name        = "${local.wiremock_name}-alb-sg"
  description = "Security group for WireMock dedicated ALB (no WAF)"
  vpc_id      = var.vpc_id

  tags = merge(local.common_tags, { Name = "${local.wiremock_name}-alb-sg" })
}

resource "aws_vpc_security_group_ingress_rule" "wiremock_alb_https" {
  count = local.wiremock_use_dedicated_alb ? 1 : 0

  security_group_id = aws_security_group.wiremock_alb[0].id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  description       = "HTTPS from internet"

  tags = local.common_tags
}

resource "aws_vpc_security_group_ingress_rule" "wiremock_alb_http" {
  count = local.wiremock_use_dedicated_alb ? 1 : 0

  security_group_id = aws_security_group.wiremock_alb[0].id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
  description       = "HTTP from internet (redirected to HTTPS)"

  tags = local.common_tags
}

resource "aws_vpc_security_group_egress_rule" "wiremock_alb_to_vpc" {
  count = local.wiremock_use_dedicated_alb ? 1 : 0

  security_group_id = aws_security_group.wiremock_alb[0].id
  cidr_ipv4         = data.aws_vpc.selected[0].cidr_block
  ip_protocol       = "-1"
  description       = "All traffic within VPC (to ECS tasks)"

  tags = local.common_tags
}

resource "aws_lb" "wiremock" { # NOSONAR - WireMock ALB is a test stub, access logs not required #checkov:skip=CKV_AWS_91
  count = local.wiremock_use_dedicated_alb ? 1 : 0

  name               = "${local.wiremock_short_uid}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.wiremock_alb[0].id]
  subnets            = var.wiremock_public_subnet_ids

  drop_invalid_header_fields = true
  enable_deletion_protection = false

  tags = local.common_tags
}

resource "aws_lb_listener" "wiremock_https" {
  count = local.wiremock_use_dedicated_alb ? 1 : 0

  load_balancer_arn = aws_lb.wiremock[0].arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.acm_regional_certificate_arn

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "application/json"
      message_body = "{\"error\":\"not_found\"}"
      status_code  = "404"
    }
  }

  tags = local.common_tags
}

resource "aws_lb_listener" "wiremock_http_redirect" {
  count = local.wiremock_use_dedicated_alb ? 1 : 0

  load_balancer_arn = aws_lb.wiremock[0].arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

  tags = local.common_tags
}

################################################################################
# ALB Target Group — registers with shared core ALB or dedicated ALB
################################################################################

resource "aws_lb_target_group" "wiremock" {
  count = var.enable_wiremock ? 1 : 0

  name        = "${local.wiremock_short_uid}-tg"
  port        = local.wiremock_container_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
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

  tags = local.common_tags
}

################################################################################
# ALB Listener Rule — host-based routing on the HTTPS listener
# Uses dedicated ALB (no WAF) when wiremock_bypass_waf = true,
# otherwise uses the shared core ALB (with WAF).
# Matches: wiremock-<env>.<account>.hometest.service.nhs.uk
################################################################################

resource "aws_lb_listener_rule" "wiremock" {
  count = var.enable_wiremock && (var.wiremock_bypass_waf || var.wiremock_alb_https_listener_arn != null) ? 1 : 0

  listener_arn = local.wiremock_effective_https_listener_arn

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.wiremock[0].arn
  }

  condition {
    host_header {
      values = [local.wiremock_domain]
    }
  }

  tags = local.common_tags
}

################################################################################
# Route53 — custom domain for WireMock
# Pattern: wiremock-<env>.<account>.hometest.service.nhs.uk
# Covered by shared wildcard cert *.poc.hometest.service.nhs.uk
################################################################################

resource "aws_route53_record" "wiremock" {
  count = var.enable_wiremock && local.wiremock_domain != null && (var.wiremock_bypass_waf || var.wiremock_alb_dns_name != null) ? 1 : 0

  zone_id = var.route53_zone_id
  name    = local.wiremock_domain
  type    = "A"

  alias {
    name                   = local.wiremock_effective_alb_dns_name
    zone_id                = local.wiremock_effective_alb_zone_id
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

  force_destroy = true

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
  version = "~> 7.5.0"

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

  capacity_provider_strategy = var.wiremock_use_spot ? {
    fargate_spot = {
      capacity_provider = "FARGATE_SPOT"
      weight            = 10
      base              = 1
    }
    } : {
    fargate = {
      capacity_provider = "FARGATE"
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

      portMappings = [{
        containerPort = local.wiremock_container_port
        protocol      = "tcp"
      }]

      readonlyRootFilesystem = false # WireMock writes mappings/files to disk

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.wiremock[0].name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "wiremock"
        }
      }

      healthCheck = {
        command     = ["CMD-SHELL", "wget -qO/dev/null http://localhost:${local.wiremock_container_port}/__admin/health || exit 1"]
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
  task_exec_iam_role_name        = "${local.wiremock_short_uid}-exec"
  task_exec_iam_role_description = "ECS task execution role for WireMock - pulls images and writes logs"

  task_exec_iam_statements = [
    {
      effect    = "Allow"
      actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
      resources = [var.kms_key_arn]
    }
  ]

  # ---------------------------------------------------------------------------
  # IAM — Task Role (container runtime permissions — minimal for WireMock)
  # ---------------------------------------------------------------------------
  tasks_iam_role_name        = "${local.wiremock_short_uid}-task"
  tasks_iam_role_description = "ECS task role for WireMock - no extra permissions needed"

  tasks_iam_role_statements = null

  # ---------------------------------------------------------------------------
  # Networking — PRIVATE subnets, no public IP
  # ---------------------------------------------------------------------------
  subnet_ids         = var.wiremock_subnet_ids # Private subnets (tasks don't need internet directly)
  assign_public_ip   = false
  enable_autoscaling = false

  # Security group — ALB + Lambda ingress; HTTPS + DNS egress
  security_group_name        = "${local.wiremock_name}-sg"
  security_group_description = "Security group for WireMock ECS tasks"

  security_group_ingress_rules = merge(
    {
      alb_ingress = {
        from_port                    = local.wiremock_container_port
        to_port                      = local.wiremock_container_port
        ip_protocol                  = "tcp"
        referenced_security_group_id = local.wiremock_effective_alb_security_group_id
        description                  = "HTTP from ALB"
      }
    },
    # Allow Lambda functions to call WireMock directly (service-to-service)
    { for idx, sg_id in var.lambda_security_group_ids : "lambda_ingress_${idx}" => {
      from_port                    = local.wiremock_container_port
      to_port                      = local.wiremock_container_port
      ip_protocol                  = "tcp"
      referenced_security_group_id = sg_id
      description                  = "HTTP from Lambda SG ${sg_id}"
    } }
  )

  security_group_egress_rules = {
    https_egress = {
      from_port   = 443
      to_port     = 443
      ip_protocol = "tcp"
      cidr_ipv4   = "0.0.0.0/0"
      description = "HTTPS outbound for ECR and CloudWatch"
    }
    dns_udp_egress = {
      from_port   = 53
      to_port     = 53
      ip_protocol = "udp"
      cidr_ipv4   = data.aws_vpc.selected[0].cidr_block
      description = "DNS (UDP)"
    }
    dns_tcp_egress = {
      from_port   = 53
      to_port     = 53
      ip_protocol = "tcp"
      cidr_ipv4   = data.aws_vpc.selected[0].cidr_block
      description = "DNS (TCP)"
    }
  }

  # ---------------------------------------------------------------------------
  # Load balancer
  # ---------------------------------------------------------------------------
  load_balancer = {
    wiremock = {
      target_group_arn = aws_lb_target_group.wiremock[0].arn
      container_name   = "wiremock"
      container_port   = local.wiremock_container_port
    }
  }

  # ---------------------------------------------------------------------------
  # Service discovery
  # ---------------------------------------------------------------------------
  service_registries = var.wiremock_service_discovery_namespace_id != null ? {
    registry_arn = aws_service_discovery_service.wiremock[0].arn
  } : null

  ignore_task_definition_changes = false

  tags = local.common_tags
}

################################################################################
# Lambda → WireMock egress rules
#
# The network module's lambda SG only opens egress on 443 and 53.
# When WireMock is enabled, lambdas must also be able to reach WireMock on
# port 8080 via internal service discovery. We attach one egress rule per
# lambda SG here rather than widening the shared lambda SG globally.
################################################################################

resource "aws_vpc_security_group_egress_rule" "lambda_to_wiremock" {
  for_each = var.enable_wiremock ? toset(var.lambda_security_group_ids) : toset([])

  security_group_id            = each.value
  referenced_security_group_id = module.wiremock_service[0].security_group_id
  from_port                    = local.wiremock_container_port
  to_port                      = local.wiremock_container_port
  ip_protocol                  = "tcp"
  description                  = "HTTP to WireMock (service discovery, port ${local.wiremock_container_port})"

  tags = merge(local.common_tags, {
    Name = "${local.wiremock_name}-lambda-egress"
  })
}

################################################################################
# Scheduled Scaling — scale to 0 outside business hours
#
# Uses Application Auto Scaling scheduled actions to set desired_count = 0
# at wiremock_scale_down_cron and back to wiremock_desired_count at
# wiremock_scale_up_cron. Only created when wiremock_scheduled_scaling = true.
################################################################################

resource "aws_appautoscaling_target" "wiremock" {
  count = var.enable_wiremock && var.wiremock_scheduled_scaling ? 1 : 0

  max_capacity       = var.wiremock_desired_count
  min_capacity       = 0
  resource_id        = "service/${var.wiremock_ecs_cluster_name}/${local.wiremock_name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"

  depends_on = [module.wiremock_service]
}

resource "aws_appautoscaling_scheduled_action" "wiremock_scale_up" {
  count = var.enable_wiremock && var.wiremock_scheduled_scaling ? 1 : 0

  name               = "${local.wiremock_name}-scale-up"
  service_namespace  = aws_appautoscaling_target.wiremock[0].service_namespace
  resource_id        = aws_appautoscaling_target.wiremock[0].resource_id
  scalable_dimension = aws_appautoscaling_target.wiremock[0].scalable_dimension
  schedule           = var.wiremock_scale_up_cron

  scalable_target_action {
    min_capacity = var.wiremock_desired_count
    max_capacity = var.wiremock_desired_count
  }
}

resource "aws_appautoscaling_scheduled_action" "wiremock_scale_down" {
  count = var.enable_wiremock && var.wiremock_scheduled_scaling ? 1 : 0

  name               = "${local.wiremock_name}-scale-down"
  service_namespace  = aws_appautoscaling_target.wiremock[0].service_namespace
  resource_id        = aws_appautoscaling_target.wiremock[0].resource_id
  scalable_dimension = aws_appautoscaling_target.wiremock[0].scalable_dimension
  schedule           = var.wiremock_scale_down_cron

  scalable_target_action {
    min_capacity = 0
    max_capacity = 0
  }
}
