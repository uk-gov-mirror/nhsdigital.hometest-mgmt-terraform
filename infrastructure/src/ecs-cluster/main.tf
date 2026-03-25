################################################################################
# ECS Cluster (Fargate) - Core Infrastructure
# Shared ECS cluster used by all environments for container workloads.
################################################################################

locals {
  resource_prefix = "${var.project_name}-${var.aws_account_shortname}-${var.environment}"

  common_tags = merge(var.tags, {
    Component = "ecs-cluster"
  })
}

################################################################################
# ECS Cluster
################################################################################

resource "aws_ecs_cluster" "main" {
  name = "${local.resource_prefix}-ecs"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  configuration {
    execute_command_configuration {
      kms_key_id = var.kms_key_arn
      logging    = "OVERRIDE"

      log_configuration {
        cloud_watch_encryption_enabled = true
        cloud_watch_log_group_name     = aws_cloudwatch_log_group.ecs_exec.name
      }
    }
  }

  tags = local.common_tags
}

################################################################################
# Fargate Capacity Providers
################################################################################

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name = aws_ecs_cluster.main.name

  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
    base              = 1
  }
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

resource "aws_cloudwatch_log_group" "ecs_tasks" {
  name              = "/ecs/${local.resource_prefix}/tasks"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn

  tags = local.common_tags
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

################################################################################
# ECS Task Security Group (shared baseline)
# Individual services should create their own SGs for ingress rules.
################################################################################

resource "aws_security_group" "ecs_tasks" {
  name        = "${local.resource_prefix}-ecs-tasks-sg"
  description = "Shared baseline security group for ECS Fargate tasks"
  vpc_id      = var.vpc_id

  egress {
    description = "HTTPS outbound for AWS APIs and ECR"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Required for ECR, CloudWatch, Secrets Manager
  }

  egress {
    description = "DNS resolution (UDP)"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "DNS resolution (TCP)"
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-ecs-tasks-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}
