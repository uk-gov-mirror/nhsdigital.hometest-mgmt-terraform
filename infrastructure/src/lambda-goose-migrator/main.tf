locals {
  resource_prefix = "${var.project_name}-${var.aws_account_shortname}-${var.environment}"

  common_tags = merge(var.tags, {
    Component = "goose-migrator"
  })
}

module "goose_migrator_lambda" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "8.7.0"

  function_name          = "${local.resource_prefix}-lambda-goose-migrator"
  handler                = "bootstrap" # Do not change - for custom runtimes, this must be 'bootstrap'
  runtime                = "provided.al2023"
  create_role            = false
  lambda_role            = aws_iam_role.lambda_goose_migrator.arn
  timeout                = 300
  memory_size            = 128
  publish                = true
  vpc_subnet_ids         = var.subnet_ids
  vpc_security_group_ids = var.security_group_ids

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-lambda-goose-migrator"
  })

  environment_variables = {
    DB_USERNAME          = var.db_username
    DB_ADDRESS           = var.db_address
    DB_PORT              = var.db_port
    DB_NAME              = var.db_name
    DB_SECRET_ARN        = data.aws_rds_cluster.db.master_user_secret[0].secret_arn
    DB_SCHEMA            = var.db_schema
    APP_USER_SECRET_NAME = var.app_user_secret_name
  }

  architectures = ["arm64"]

  recreate_missing_package = true

  source_path = [
    {
      path = "${path.module}/src"
      commands = [
        "go mod tidy",
        "GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build -o bootstrap main.go",
        ":zip",
      ]
      patterns = [
        "!.*",
        "bootstrap",
        "migrations/.*",
      ]
    }
  ]
}
