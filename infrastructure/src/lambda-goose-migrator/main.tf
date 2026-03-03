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
    DB_SCHEMA            = var.db_schema
    DB_REGION            = var.aws_region
    USE_IAM_AUTH         = tostring(var.use_iam_auth)
    DB_SECRET_ARN        = var.use_iam_auth ? "" : data.aws_rds_cluster.db.master_user_secret[0].secret_arn
    APP_USER_SECRET_NAME = var.db_schema != "public" ? aws_secretsmanager_secret.app_user[0].name : ""
    GRANT_RDS_IAM        = tostring(var.grant_rds_iam)
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
        "migrations/.*",
      ]
    }
  ]
}

# ---------------------------------------------------------------------------------------------------------------------
# APP USER SECRET - Terraform-managed credentials for schema-scoped app_user
#
# Creates a random password and stores it in Secrets Manager. The goose migrator
# Lambda reads this password to CREATE/ALTER the DB role. App lambdas also read
# it for their DB connections.
#
# Only created when db_schema != "public" (i.e., for per-environment schemas).
# Password rotation: taint random_password.app_user_password and re-apply.
# ---------------------------------------------------------------------------------------------------------------------

resource "random_password" "app_user_password" {
  count   = var.db_schema != "public" ? 1 : 0
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret" "app_user" {
  count       = var.db_schema != "public" ? 1 : 0
  name        = var.app_user_secret_name
  description = "Database credentials for app_user_${var.db_schema} (schema-scoped)"

  tags = merge(local.common_tags, {
    Name = var.app_user_secret_name
  })
}

resource "aws_secretsmanager_secret_version" "app_user" {
  count     = var.db_schema != "public" ? 1 : 0
  secret_id = aws_secretsmanager_secret.app_user[0].id
  secret_string = jsonencode({
    username = "app_user_${var.db_schema}"
    password = random_password.app_user_password[0].result
    host     = var.db_address
    port     = var.db_port
    dbname   = var.db_name
    engine   = "postgres"
  })
}
