################################################################################
# Per-Lambda IAM Role (Least Privilege)
#
# Each Lambda function gets its own dedicated IAM role with only the
# permissions it needs. This replaces the shared role pattern and enforces
# the principle of least privilege.
################################################################################

resource "aws_iam_role" "this" {
  name                 = "${local.function_name}-role"
  description          = "Execution role for ${local.function_name}"
  max_session_duration = var.max_session_duration

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "LambdaAssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
        Condition = var.restrict_to_account ? {
          StringEquals = {
            "aws:SourceAccount" = var.aws_account_id
          }
        } : null
      }
    ]
  })

  tags = merge(local.common_tags, {
    ResourceType = "iam-role"
  })
}

################################################################################
# CloudWatch Logs — always attached (required for Lambda execution)
################################################################################

resource "aws_iam_role_policy" "cloudwatch_logs" {
  name = "${local.function_name}-cw-logs"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "CreateLogGroup"
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup"]
        Resource = "arn:aws:logs:${var.aws_region}:${var.aws_account_id}:*"
      },
      {
        Sid    = "WriteToCloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${var.aws_account_id}:log-group:/aws/lambda/${local.function_name}:*"
      }
    ]
  })
}

################################################################################
# X-Ray Tracing (conditional)
################################################################################

resource "aws_iam_role_policy" "xray" {
  count = var.enable_xray ? 1 : 0

  name = "${local.function_name}-xray"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "XRayTracing"
        Effect = "Allow"
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords",
          "xray:GetSamplingRules",
          "xray:GetSamplingTargets",
          "xray:GetSamplingStatisticSummaries"
        ]
        Resource = "*"
      }
    ]
  })
}

################################################################################
# VPC Access (conditional)
# Required for Lambda functions deployed in a VPC.
# Note: These permissions must be granted on Resource "*" as Lambda creates
# ENIs during function creation and the specific resource ARN is not known
# in advance. Security is enforced through VPC security groups.
################################################################################

resource "aws_iam_role_policy" "vpc_access" {
  count = var.enable_vpc_access ? 1 : 0

  name = "${local.function_name}-vpc"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "VPCNetworkInterfaces"
        Effect = "Allow"
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface",
          "ec2:AssignPrivateIpAddresses",
          "ec2:UnassignPrivateIpAddresses"
        ]
        Resource = "*"
      }
    ]
  })
}

################################################################################
# Secrets Manager (conditional — only secrets this Lambda needs)
################################################################################

resource "aws_iam_role_policy" "secrets_manager" {
  count = length(var.secrets_arns) > 0 ? 1 : 0

  name = "${local.function_name}-secrets"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SecretsManagerRead"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = var.secrets_arns
      }
    ]
  })
}

################################################################################
# SSM Parameter Store (conditional)
################################################################################

resource "aws_iam_role_policy" "ssm_parameters" {
  count = length(var.ssm_parameter_arns) > 0 ? 1 : 0

  name = "${local.function_name}-ssm"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SSMParameterRead"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath"
        ]
        Resource = var.ssm_parameter_arns
      }
    ]
  })
}

################################################################################
# KMS Decrypt (conditional)
################################################################################

resource "aws_iam_role_policy" "kms_decrypt" {
  count = length(var.kms_key_arns) > 0 ? 1 : 0

  name = "${local.function_name}-kms"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "KMSDecrypt"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = var.kms_key_arns
      }
    ]
  })
}

################################################################################
# S3 Access (conditional)
################################################################################

resource "aws_iam_role_policy" "s3_access" {
  count = length(var.s3_bucket_arns) > 0 ? 1 : 0

  name = "${local.function_name}-s3"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3ReadWrite"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = concat(
          var.s3_bucket_arns,
          [for arn in var.s3_bucket_arns : "${arn}/*"]
        )
      }
    ]
  })
}

################################################################################
# DynamoDB Access (conditional)
################################################################################

resource "aws_iam_role_policy" "dynamodb_access" {
  count = length(var.dynamodb_table_arns) > 0 ? 1 : 0

  name = "${local.function_name}-dynamodb"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DynamoDBAccess"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query",
          "dynamodb:Scan",
          "dynamodb:BatchGetItem",
          "dynamodb:BatchWriteItem"
        ]
        Resource = concat(
          var.dynamodb_table_arns,
          [for arn in var.dynamodb_table_arns : "${arn}/index/*"]
        )
      }
    ]
  })
}

################################################################################
# SQS Send (conditional — queues this Lambda can write to)
################################################################################

resource "aws_iam_role_policy" "sqs_send" {
  count = length(var.sqs_send_queue_arns) > 0 ? 1 : 0

  name = "${local.function_name}-sqs-send"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SQSSend"
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl"
        ]
        Resource = var.sqs_send_queue_arns
      }
    ]
  })
}

################################################################################
# SQS Receive (conditional — queues this Lambda consumes from)
################################################################################

resource "aws_iam_role_policy" "sqs_receive" {
  count = length(var.sqs_receive_queue_arns) > 0 ? 1 : 0

  name = "${local.function_name}-sqs-recv"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SQSReceive"
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = var.sqs_receive_queue_arns
      }
    ]
  })
}

################################################################################
# Aurora IAM Authentication (conditional)
# Allows the Lambda to connect to Aurora clusters using IAM auth
# (rds-db:connect) instead of a static password.
################################################################################

resource "aws_iam_role_policy" "aurora_iam_auth" {
  count = length(var.aurora_cluster_resource_ids) > 0 ? 1 : 0

  name = "${local.function_name}-aurora-iam"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AuroraIAMAuthentication"
        Effect = "Allow"
        Action = "rds-db:connect"
        Resource = [
          for resource_id in var.aurora_cluster_resource_ids :
          "arn:aws:rds-db:${var.aws_region}:${var.aws_account_id}:dbuser:${resource_id}/*"
        ]
      }
    ]
  })
}

################################################################################
# Custom Policies (conditional)
################################################################################

resource "aws_iam_role_policy" "custom" {
  for_each = var.custom_policies

  name   = "${local.function_name}-${each.key}"
  role   = aws_iam_role.this.id
  policy = each.value
}

################################################################################
# Managed Policy Attachments (conditional)
################################################################################

resource "aws_iam_role_policy_attachment" "managed_policies" {
  for_each = toset(var.managed_policy_arns)

  role       = aws_iam_role.this.name
  policy_arn = each.value
}
