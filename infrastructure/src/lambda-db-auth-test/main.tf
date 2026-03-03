locals {
  resource_prefix = "${var.project_name}-${var.aws_account_shortname}-${var.environment}"

  common_tags = merge(var.tags, {
    Component = "db-auth-test"
  })
}

# ---------------------------------------------------------------------------------------------------------------------
# LAMBDA FUNCTION — lightweight IAM auth tester
# Connects as app_user_<schema> using an IAM token and runs basic diagnostic queries.
# ---------------------------------------------------------------------------------------------------------------------

module "db_auth_test_lambda" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "8.7.0"

  function_name          = "${local.resource_prefix}-lambda-db-auth-test"
  handler                = "bootstrap"
  runtime                = "provided.al2023"
  create_role            = false
  lambda_role            = aws_iam_role.db_auth_test.arn
  timeout                = 30
  memory_size            = 128
  publish                = true
  vpc_subnet_ids         = var.subnet_ids
  vpc_security_group_ids = var.security_group_ids

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-lambda-db-auth-test"
  })

  environment_variables = {
    DB_USERNAME          = "app_user_${var.db_schema}"
    DB_ADDRESS           = var.db_address
    DB_PORT              = var.db_port
    DB_NAME              = var.db_name
    DB_SCHEMA            = var.db_schema
    DB_REGION            = var.aws_region
    APP_USER_SECRET_NAME = var.app_user_secret_name
  }

  architectures = ["arm64"]

  recreate_missing_package = true

  source_path = [
    {
      path = "${path.module}/src"
      commands = [
        "go mod tidy",
        "GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build -trimpath -ldflags='-s -w' -o bootstrap main.go",
        ":zip",
      ]
      patterns = [
        "!.*",
        "bootstrap",
      ]
    }
  ]
}

# ---------------------------------------------------------------------------------------------------------------------
# IAM ROLE — minimal permissions: VPC networking + rds-db:connect (IAM auth)
# No Secrets Manager access needed — this lambda uses IAM tokens only.
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_iam_role" "db_auth_test" {
  name = "${local.resource_prefix}-db-auth-test-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-db-auth-test-role"
  })
}

resource "aws_iam_role_policy" "db_auth_test" {
  name = "${local.resource_prefix}-db-auth-test-policy"
  role = aws_iam_role.db_auth_test.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "Logs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = ["arn:aws:logs:*:*:*"]
      },
      {
        Sid      = "RdsIamAuth"
        Effect   = "Allow"
        Action   = ["rds-db:connect"]
        Resource = ["*"]
      },
      {
        Sid      = "SecretsManager"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = ["*"]
      },
      {
        Sid    = "VpcNetworking"
        Effect = "Allow"
        Action = [
          "ec2:DescribeNetworkInterfaces",
          "ec2:CreateNetworkInterface",
          "ec2:DeleteNetworkInterface",
          "ec2:DescribeInstances",
          "ec2:AttachNetworkInterface"
        ]
        Resource = ["*"]
      }
    ]
  })
}
