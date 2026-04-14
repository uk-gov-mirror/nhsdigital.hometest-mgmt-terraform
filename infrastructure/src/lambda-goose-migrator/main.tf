locals {
  resource_prefix = "${var.project_name}-${var.aws_account_shortname}-${var.environment}"

  common_tags = merge(var.tags, {
    Component = "goose-migrator"
  })
}

module "goose_migrator_lambda" {
  source = "../../modules/lambda"

  project_name          = var.project_name
  aws_account_shortname = var.aws_account_shortname
  function_name         = "lambda-goose-migrator"
  environment           = var.environment
  lambda_role_arn       = aws_iam_role.lambda_goose_migrator.arn

  filename         = var.goose_migrator_zip_path
  source_code_hash = filebase64sha256(var.goose_migrator_zip_path)

  handler     = "bootstrap"
  runtime     = "provided.al2023"
  timeout     = 300
  memory_size = 128

  architectures = ["arm64"]

  function_name          = "${local.resource_prefix}-lambda-goose-migrator"
  description            = "Lambda function for running Goose DB migrations (Go, custom runtime)"
  handler                = "bootstrap" # Do not change - for custom runtimes, this must be 'bootstrap'
  runtime                = "provided.al2023"
  create_role            = false
  lambda_role            = aws_iam_role.lambda_goose_migrator.arn
  timeout                = 300
  memory_size            = 128
  publish                = true
  vpc_subnet_ids         = var.subnet_ids
  vpc_security_group_ids = var.security_group_ids

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

  tags = local.common_tags
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
  count                   = var.db_schema != "public" ? 1 : 0
  name                    = var.app_user_secret_name
  description             = "Database credentials for app_user_${var.db_schema} (schema-scoped)"
  recovery_window_in_days = 0
  kms_key_id              = var.kms_key_arn

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
