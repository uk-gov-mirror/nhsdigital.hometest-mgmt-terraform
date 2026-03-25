################################################################################
# WireMock ECS Service (Fargate)
#
# Deploys the official WireMock Docker image on ECS Fargate for:
# - Stubbing 3rd-party APIs in dev environments
# - Providing a mock backend for Playwright end-to-end tests
#
# Service is only created when var.enable_wiremock = true.
# Service discovery is used so other services can reach WireMock at:
#   wiremock.<namespace>.local:8080
################################################################################

locals {
  wiremock_name           = "${local.resource_prefix}-wiremock"
  wiremock_container_port = 8080
}

################################################################################
# ECS Task Execution Role (pulls image, writes logs)
################################################################################

resource "aws_iam_role" "wiremock_execution" {
  count = var.enable_wiremock ? 1 : 0

  name = "${local.wiremock_name}-exec-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = merge(local.common_tags, {
    Name = "${local.wiremock_name}-exec-role"
  })
}

resource "aws_iam_role_policy_attachment" "wiremock_execution" {
  count = var.enable_wiremock ? 1 : 0

  role       = aws_iam_role.wiremock_execution[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "wiremock_execution_kms" {
  count = var.enable_wiremock ? 1 : 0

  name = "${local.wiremock_name}-exec-kms"
  role = aws_iam_role.wiremock_execution[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "kms:Decrypt",
        "kms:GenerateDataKey"
      ]
      Resource = [var.kms_key_arn]
    }]
  })
}

################################################################################
# ECS Task Role (the running container's permissions — minimal for WireMock)
################################################################################

resource "aws_iam_role" "wiremock_task" {
  count = var.enable_wiremock ? 1 : 0

  name = "${local.wiremock_name}-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
      Condition = {
        ArnLike = {
          "aws:SourceArn" = "arn:aws:ecs:${var.aws_region}:${var.aws_account_id}:*"
        }
        StringEquals = {
          "aws:SourceAccount" = var.aws_account_id
        }
      }
    }]
  })

  tags = merge(local.common_tags, {
    Name = "${local.wiremock_name}-task-role"
  })
}

################################################################################
# CloudWatch Log Group for WireMock
################################################################################

resource "aws_cloudwatch_log_group" "wiremock" {
  count = var.enable_wiremock ? 1 : 0

  name              = "/ecs/${local.wiremock_name}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn

  tags = local.common_tags
}

################################################################################
# Security Group for WireMock
################################################################################

resource "aws_security_group" "wiremock" {
  count = var.enable_wiremock ? 1 : 0

  name        = "${local.wiremock_name}-sg"
  description = "Security group for WireMock ECS service"
  vpc_id      = var.vpc_id

  # Ingress: allow traffic from the ALB only
  ingress {
    description     = "HTTP from ALB"
    from_port       = local.wiremock_container_port
    to_port         = local.wiremock_container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.wiremock_alb[0].id]
  }

  # Ingress: allow traffic from Lambda security groups (for direct service-to-service calls)
  dynamic "ingress" {
    for_each = length(var.lambda_security_group_ids) > 0 ? [1] : []
    content {
      description     = "HTTP from Lambda functions"
      from_port       = local.wiremock_container_port
      to_port         = local.wiremock_container_port
      protocol        = "tcp"
      security_groups = var.lambda_security_group_ids
    }
  }

  # Egress: HTTPS for health check callbacks and AWS API calls
  egress {
    description = "HTTPS outbound"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Egress: DNS
  egress {
    description = "DNS (UDP)"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = [data.aws_vpc.selected[0].cidr_block]
  }

  egress {
    description = "DNS (TCP)"
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.selected[0].cidr_block]
  }

  tags = merge(local.common_tags, {
    Name = "${local.wiremock_name}-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

################################################################################
# Application Load Balancer for WireMock
################################################################################

data "aws_vpc" "selected" {
  count = var.enable_wiremock ? 1 : 0
  id    = var.vpc_id
}

resource "aws_security_group" "wiremock_alb" {
  count = var.enable_wiremock ? 1 : 0

  name        = "${local.wiremock_name}-alb-sg"
  description = "Security group for WireMock ALB — restricts access to VPC CIDR only"
  vpc_id      = var.vpc_id

  # Only allow traffic from within the VPC (Lambdas, other services, VPN)
  ingress {
    description = "HTTP from VPC"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.selected[0].cidr_block]
  }

  egress {
    description     = "To WireMock targets"
    from_port       = local.wiremock_container_port
    to_port         = local.wiremock_container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.wiremock[0].id]
  }

  tags = merge(local.common_tags, {
    Name = "${local.wiremock_name}-alb-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb" "wiremock" {
  count = var.enable_wiremock ? 1 : 0

  name               = "${local.wiremock_name}-alb"
  internal           = true # Not exposed to internet
  load_balancer_type = "application"
  security_groups    = [aws_security_group.wiremock_alb[0].id]
  subnets            = var.wiremock_subnet_ids

  enable_deletion_protection = false
  drop_invalid_header_fields = true

  tags = local.common_tags
}

resource "aws_lb_target_group" "wiremock" {
  count = var.enable_wiremock ? 1 : 0

  name        = "${local.wiremock_name}-tg"
  port        = local.wiremock_container_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip" # Required for Fargate awsvpc networking

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

resource "aws_lb_listener" "wiremock" {
  count = var.enable_wiremock ? 1 : 0

  load_balancer_arn = aws_lb.wiremock[0].arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.wiremock[0].arn
  }

  tags = local.common_tags
}

################################################################################
# ECS Task Definition
################################################################################

resource "aws_ecs_task_definition" "wiremock" {
  count = var.enable_wiremock ? 1 : 0

  family                   = local.wiremock_name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.wiremock_cpu
  memory                   = var.wiremock_memory
  execution_role_arn       = aws_iam_role.wiremock_execution[0].arn
  task_role_arn            = aws_iam_role.wiremock_task[0].arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([{
    name      = "wiremock"
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
      command     = ["CMD-SHELL", "wget --spider --quiet http://localhost:${local.wiremock_container_port}/__admin/health || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 15
    }
  }])

  tags = local.common_tags
}

################################################################################
# Service Discovery for WireMock
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
# ECS Service
################################################################################

resource "aws_ecs_service" "wiremock" {
  count = var.enable_wiremock ? 1 : 0

  name            = local.wiremock_name
  cluster         = var.wiremock_ecs_cluster_arn
  task_definition = aws_ecs_task_definition.wiremock[0].arn
  desired_count   = var.wiremock_desired_count
  launch_type     = "FARGATE"

  # Allow new deployments to stabilise before stopping old tasks
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = var.wiremock_subnet_ids
    security_groups  = [aws_security_group.wiremock[0].id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.wiremock[0].arn
    container_name   = "wiremock"
    container_port   = local.wiremock_container_port
  }

  dynamic "service_registries" {
    for_each = var.wiremock_service_discovery_namespace_id != null ? [1] : []
    content {
      registry_arn = aws_service_discovery_service.wiremock[0].arn
    }
  }

  # Ignore desired_count changes (auto-scaling or manual adjustments)
  lifecycle {
    ignore_changes = [desired_count]
  }

  tags = local.common_tags
}
