# ---------------------------------------------------------------------------------------------------------------------
# COMMON TERRAGRUNT CONFIGURATION FOR HOMETEST-APP
# Location: poc/hometest-app/app.hcl
#
# Shared configuration for all environments (dev, dev-mikmio, etc.) under poc/hometest-app/.
# Environment-specific terragrunt.hcl files include this and override only what's needed.
#
# Environment name is derived automatically from the child directory name (e.g., dev/, dev-mikmio/).
#
# Usage in child terragrunt.hcl:
#   include "app" {
#     path           = find_in_parent_folders("app.hcl")
#     expose         = true
#     merge_strategy = "deep"
#   }
#
# To add environment-specific overrides (e.g., extra lambdas), define an inputs block
# in the child terragrunt.hcl — it will be deep-merged with the inputs below.
# ---------------------------------------------------------------------------------------------------------------------

# ---------------------------------------------------------------------------------------------------------------------
# LOCALS - Common configuration values
# ---------------------------------------------------------------------------------------------------------------------

locals {
  # Load configuration from parent folders
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  global_vars  = read_terragrunt_config(find_in_parent_folders("_envcommon/all.hcl"))

  # Environment derived from child directory name (e.g., dev/, dev-mikmio/)
  environment = basename(get_terragrunt_dir())

  # Extract commonly used values
  project_name          = local.global_vars.locals.project_name
  account_id            = local.account_vars.locals.aws_account_id
  aws_account_shortname = local.account_vars.locals.aws_account_shortname
  aws_region            = local.global_vars.locals.aws_region

  # Domain configuration
  base_domain = "hometest.service.nhs.uk"
  env_domain  = "${local.environment}.${local.base_domain}"

  # Schema-per-environment: each env gets its own schema in the shared Aurora DB
  db_schema            = "hometest_${local.environment}"
  app_user_secret_name = "nhs-hometest/${local.environment}/app-user-db-secret"

  # ---------------------------------------------------------------------------
  # SOURCE PATHS
  # Override these in child terragrunt.hcl locals if needed
  # ---------------------------------------------------------------------------
  lambdas_source_dir = "${get_repo_root()}/../hometest-service/lambdas"
  lambdas_base_path  = "${local.lambdas_source_dir}/src"
  spa_source_dir     = "${get_repo_root()}/../hometest-service/ui"
  spa_dist_dir       = "${local.spa_source_dir}/out"
  spa_type           = "nextjs" # "nextjs" or "vite"

  # Lambda Configuration Defaults
  # https://docs.aws.amazon.com/lambda/latest/dg/lambda-runtimes.html
  lambda_runtime     = "nodejs24.x"
  lambda_timeout     = 30
  lambda_memory_size = 256
  log_retention_days = 14

  # API Gateway Defaults
  api_stage_name             = "v1"
  api_endpoint_type          = "REGIONAL"
  api_throttling_burst_limit = 1000
  api_throttling_rate_limit  = 2000

  # CloudFront Defaults
  cloudfront_price_class = "PriceClass_100"

  # Security headers
  content_security_policy = "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; font-src 'self' data:; connect-src 'self' https:; frame-ancestors 'none';"
  permissions_policy      = "accelerometer=(), camera=(), geolocation=(), gyroscope=(), magnetometer=(), microphone=(), payment=(), usb=()"
}

# ---------------------------------------------------------------------------------------------------------------------
# TERRAFORM SOURCE
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/infrastructure//src/hometest-app"

  # ---------------------------------------------------------------------------
  # BUILD HOOKS
  # These hooks build and package artifacts locally BEFORE terraform runs.
  # Terraform then uploads and deploys the Lambda functions.
  # Paths are configurable via locals: lambdas_source_dir, spa_source_dir, spa_type
  # ---------------------------------------------------------------------------

  # Build and package Lambda code locally (Terraform uploads and deploys)
  # Uses scripts/build-lambdas.sh which only rebuilds when source changes are detected
  before_hook "build_lambdas" {
    commands = ["plan",
    "apply"]
    execute = [
      "bash", "-c",
      "\"$(cd '${get_repo_root()}' && pwd)/scripts/build-lambdas.sh\" \"$(cd '${local.lambdas_source_dir}' && pwd)\" \"$(cd '${get_repo_root()}' && pwd)/.lambda-build-cache\""
    ]
  }

  # Build SPA before apply
  before_hook "build_spa" {
    commands = ["apply"]
    execute = [
      "bash", "-c",
      <<-EOF
        SPA_DIR="${local.spa_source_dir}"
        SPA_TYPE="${local.spa_type}"
        if [[ -d "$SPA_DIR" ]] && [[ -f "$SPA_DIR/package.json" ]]; then
          echo "Building $SPA_TYPE SPA from $SPA_DIR..."
          cd "$SPA_DIR"
          npm ci --silent 2>/dev/null || npm install --silent

          export NEXT_PUBLIC_BACKEND_URL="https://${local.env_domain}"
          echo "Setting NEXT_PUBLIC_BACKEND_URL=$NEXT_PUBLIC_BACKEND_URL"

          npm run build --silent 2>/dev/null || true
          echo "SPA build complete!"
        else
          echo "SPA not found at $SPA_DIR, skipping..."
        fi
      EOF
    ]
  }

  # Upload SPA to S3 after terraform creates the bucket
  after_hook "upload_spa" {
    commands     = ["apply"]
    run_on_error = false
    execute = [
      "bash", "-c",
      <<-EOF
        SPA_TYPE="${local.spa_type}"
        SPA_DIST="${local.spa_dist_dir}"

        # Fallback paths based on SPA type
        if [[ ! -d "$SPA_DIST" ]]; then
          if [[ "$SPA_TYPE" == "nextjs" ]]; then
            SPA_DIST="${local.spa_source_dir}/build"
          else
            SPA_DIST="${local.spa_source_dir}/dist"
          fi
        fi

        if [[ -d "$SPA_DIST" ]]; then
          SPA_BUCKET=$(terraform output -raw spa_bucket_id 2>/dev/null || echo "")
          if [[ -n "$SPA_BUCKET" ]]; then
            echo "Uploading $SPA_TYPE SPA from $SPA_DIST to s3://$SPA_BUCKET..."

            if [[ "$SPA_TYPE" == "nextjs" ]]; then
              # Next.js specific upload with proper caching
              aws s3 sync "$SPA_DIST" "s3://$SPA_BUCKET" \
                --delete \
                --cache-control "max-age=31536000" \
                --exclude "*.html" \
                --exclude "_next/data/*" \
                --region eu-west-2
              # HTML files with no-cache
              aws s3 cp "$SPA_DIST" "s3://$SPA_BUCKET" \
                --recursive \
                --exclude "*" \
                --include "*.html" \
                --cache-control "no-cache, no-store, must-revalidate" \
                --region eu-west-2
              # _next/data with short cache
              if [[ -d "$SPA_DIST/_next/data" ]]; then
                aws s3 sync "$SPA_DIST/_next/data" "s3://$SPA_BUCKET/_next/data" \
                  --cache-control "max-age=60" \
                  --region eu-west-2
              fi
            else
              # Vite/standard SPA upload
              aws s3 sync "$SPA_DIST" "s3://$SPA_BUCKET" \
                --delete \
                --cache-control "max-age=31536000" \
                --exclude "index.html" \
                --region eu-west-2
              aws s3 cp "$SPA_DIST/index.html" "s3://$SPA_BUCKET/index.html" \
                --cache-control "no-cache, no-store, must-revalidate" \
                --region eu-west-2
            fi
            echo "SPA uploaded successfully!"

            # Invalidate CloudFront cache
            CLOUDFRONT_ID=$(terraform output -raw cloudfront_distribution_id 2>/dev/null || echo "")
            if [[ -n "$CLOUDFRONT_ID" ]]; then
              echo "Invalidating CloudFront cache for distribution $CLOUDFRONT_ID..."
              aws cloudfront create-invalidation \
                --distribution-id "$CLOUDFRONT_ID" \
                --paths "/*" \
                --output text
              echo "CloudFront cache invalidation initiated!"
            fi
          else
            echo "Could not determine SPA bucket, skipping upload..."
          fi
        else
          echo "No SPA dist found at $SPA_DIST, skipping upload..."
        fi
      EOF
    ]
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPENDENCIES
# These are shared across all hometest-app environments.
# Config paths are resolved relative to the child terragrunt.hcl that includes this file.
# ---------------------------------------------------------------------------------------------------------------------

dependency "network" {
  config_path = "${get_terragrunt_dir()}/../../core/network"

  mock_outputs = {
    route53_zone_id              = "Z0123456789ABCDEFGHIJ"
    vpc_id                       = "vpc-mock12345"
    private_subnet_ids           = ["subnet-mock1", "subnet-mock2", "subnet-mock3"]
    lambda_security_group_id     = "sg-mock12345"
    lambda_rds_security_group_id = "sg-mock67890"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

dependency "shared_services" {
  config_path = "${get_terragrunt_dir()}/../../core/shared_services"

  mock_outputs = {
    kms_key_arn                     = "arn:aws:kms:eu-west-2:123456789012:key/mock-key-id"
    sns_alerts_topic_arn            = "arn:aws:sns:eu-west-2:123456789012:mock-alerts-topic"
    waf_regional_arn                = "arn:aws:wafv2:eu-west-2:123456789012:regional/webacl/mock/mock-id"
    waf_cloudfront_arn              = "arn:aws:wafv2:us-east-1:123456789012:global/webacl/mock/mock-id"
    acm_regional_certificate_arn    = "arn:aws:acm:eu-west-2:123456789012:certificate/mock-cert"
    acm_cloudfront_certificate_arn  = "arn:aws:acm:us-east-1:123456789012:certificate/mock-cert"
    deployment_artifacts_bucket_id  = "mock-deployment-bucket"
    deployment_artifacts_bucket_arn = "arn:aws:s3:::mock-deployment-bucket"
    api_config_secret_arn           = "arn:aws:secretsmanager:eu-west-2:123456789012:secret:mock-secret"
    api_config_secret_name          = "mock/secret/name"
    cognito_user_pool_arn           = "arn:aws:cognito-idp:eu-west-2:123456789012:userpool/eu-west-2_mockpool"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

dependency "aurora_postgres" {
  config_path = "${get_terragrunt_dir()}/../../core/aurora-postgres"

  mock_outputs = {
    connection_string               = "postgresql://mock-user:mock-pass@mock-aurora-cluster.cluster-abc123.eu-west-2.rds.amazonaws.com:5432/hometest"
    cluster_resource_id             = "cluster-MOCKRESOURCEID1234"
    cluster_master_username         = "mock-master-user"
    cluster_endpoint                = "mock-aurora-cluster.cluster-abc123.eu-west-2.rds.amazonaws.com"
    cluster_port                    = 5432
    cluster_database_name           = "hometest"
    cluster_master_user_secret_arn  = "arn:aws:secretsmanager:eu-west-2:123456789012:secret:mock-aurora-secret"
    cluster_master_user_secret_name = "mock-aurora-secret"
  }

  # mock_outputs_merge_with_state           = true
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

# ---------------------------------------------------------------------------------------------------------------------
# INPUTS - Shared across all hometest-app environments
# Environment-specific terragrunt.hcl files can override any of these via deep merge.
# To add extra lambdas, define an inputs block with a lambdas map in the child.
# ---------------------------------------------------------------------------------------------------------------------

inputs = {
  project_name = local.project_name
  environment  = local.environment

  # Dependencies from network
  vpc_id            = dependency.network.outputs.vpc_id
  lambda_subnet_ids = dependency.network.outputs.private_subnet_ids
  lambda_security_group_ids = [
    dependency.network.outputs.lambda_security_group_id,
    dependency.network.outputs.lambda_rds_security_group_id
  ]
  route53_zone_id = dependency.network.outputs.route53_zone_id

  # Dependencies from shared_services
  kms_key_arn          = dependency.shared_services.outputs.kms_key_arn
  sns_alerts_topic_arn = dependency.shared_services.outputs.sns_alerts_topic_arn
  waf_cloudfront_arn   = dependency.shared_services.outputs.waf_cloudfront_arn

  # Lambda Configuration
  enable_vpc_access  = true
  lambda_runtime     = local.lambda_runtime
  lambda_timeout     = local.lambda_timeout
  lambda_memory_size = local.lambda_memory_size
  log_retention_days = local.log_retention_days

  # IAM Permissions - Grant Lambda access to secrets
  # Note: AWS Secrets Manager ARNs have a random suffix, use -* wildcard to match
  lambda_secrets_arns = [
    "arn:aws:secretsmanager:eu-west-2:781863586270:secret:nhs-hometest/dev/preventex-dev-client-secret-*",
    "arn:aws:secretsmanager:eu-west-2:781863586270:secret:nhs-hometest/dev/sh24-dev-client-secret-*",
    "arn:aws:secretsmanager:eu-west-2:781863586270:secret:nhs-hometest/dev/nhs-login-private-key-*",
    "arn:aws:secretsmanager:eu-west-2:781863586270:secret:rds!cluster-*",
    # Schema-scoped app_user secret (created by goose migrator)
    "arn:aws:secretsmanager:eu-west-2:781863586270:secret:nhs-hometest/*/app-user-db-secret-*"
  ]

  # KMS keys for secrets encrypted with different keys than shared_services KMS
  lambda_additional_kms_key_arns = []

  # lambda_sqs_queue_arns is not needed here — order-placement ARN is automatically included
  # in lambda_iam.tf via module.sqs_order_placement.queue_arn

  # Aurora IAM authentication - allow Lambdas to connect without passwords
  lambda_aurora_cluster_resource_ids = [dependency.aurora_postgres.outputs.cluster_resource_id]
  # Cognito User Pool for API Gateway authorizer
  enable_cognito        = true
  cognito_user_pool_arn = dependency.shared_services.outputs.cognito_user_pool_arn

  # API prefixes that require authorization
  authorized_api_prefixes = ["result"]

  # Lambda code deployment
  use_placeholder_lambda = false

  # Base path for hometest-service lambdas
  lambdas_base_path = local.lambdas_base_path

  # =============================================================================
  # LAMBDA DEFINITIONS - hometest-service lambdas
  # Based on hometest-service/local-environment/infra/main.tf configuration
  #
  # CloudFront Routing (path-based):
  # - / and /*              → S3 SPA (Next.js)
  # - /test-order/*         → API Gateway → eligibility-test-info-lambda
  # - /order-router/*       → API Gateway → order-router-lambda (SQS-triggered)
  # - /order-router-sh24/*  → API Gateway → order-router-lambda-sh24 (SQS-triggered)
  # - /login/*              → API Gateway → login-lambda
  # - /result/*             → API Gateway → order-result-lambda
  #
  # To add extra lambdas (e.g., hello-world), define them in the child terragrunt.hcl:
  #   inputs = { lambdas = { "hello-world-lambda" = { ... } } }
  # =============================================================================
  lambdas = {
    # Eligibility Lookup Lambda
    # CloudFront: /eligibility-lookup/* → API Gateway → Lambda
    # Handles: GET /eligibility-lookup (returns eligibility information from DB)
    "eligibility-lookup-lambda" = {
      description     = "Eligibility Lookup Service - Returns eligibility information"
      api_path_prefix = "eligibility-lookup"
      handler         = "index.handler"
      timeout         = 30
      memory_size     = 256
      environment = {
        NODE_OPTIONS   = "--enable-source-maps"
        ENVIRONMENT    = local.environment
        DB_USERNAME    = "app_user_${local.db_schema}"
        DB_ADDRESS     = dependency.aurora_postgres.outputs.cluster_endpoint
        DB_PORT        = tostring(dependency.aurora_postgres.outputs.cluster_port)
        DB_NAME        = dependency.aurora_postgres.outputs.cluster_database_name
        DB_SECRET_NAME = local.app_user_secret_name
        DB_SCHEMA      = local.db_schema
      }
    }

    # Order Router Lambda - SQS triggered for async order processing
    # NOT exposed via API Gateway - processes orders from SQS queue
    "order-router-lambda" = {
      description = "Order Router Service - Processes orders from SQS queue"
      sqs_trigger = true # Triggered by SQS, no API Gateway endpoint
      # api_path_prefix = "order-router" # Not used for routing since this is SQS-triggered, but included for consistency
      handler     = "index.handler"
      timeout     = 60 # Longer timeout for external API calls to supplier
      memory_size = 512
      environment = {
        NODE_OPTIONS   = "--enable-source-maps"
        ENVIRONMENT    = local.environment
        DB_USERNAME    = "app_user_${local.db_schema}"
        DB_ADDRESS     = dependency.aurora_postgres.outputs.cluster_endpoint
        DB_PORT        = tostring(dependency.aurora_postgres.outputs.cluster_port)
        DB_NAME        = dependency.aurora_postgres.outputs.cluster_database_name
        DB_SECRET_NAME = local.app_user_secret_name
        DB_SCHEMA      = local.db_schema
      }
    }

    # Login Lambda - NHS Login authentication
    # CloudFront: /login/* → API Gateway → Lambda
    # CORS: handled in-code via @middy/http-cors using COOKIE_ACCESS_CONTROL_ALLOW_ORIGIN env var
    "login-lambda" = {
      description     = "Login Service - NHS Login authentication"
      api_path_prefix = "login"
      handler         = "index.handler"
      timeout         = 30
      memory_size     = 256
      environment = {
        NODE_OPTIONS                               = "--enable-source-maps"
        ENVIRONMENT                                = local.environment
        NHS_LOGIN_BASE_ENDPOINT_URL                = "https://auth.sandpit.signin.nhs.uk"
        NHS_LOGIN_CLIENT_ID                        = "hometest"
        NHS_LOGIN_REDIRECT_URL                     = "https://${local.env_domain}/callback"
        NHS_LOGIN_PRIVATE_KEY_SECRET_NAME          = "nhs-hometest/dev/nhs-login-private-key"
        AUTH_SESSION_MAX_DURATION_MINUTES          = "60"
        AUTH_ACCESS_TOKEN_EXPIRY_DURATION_MINUTES  = "60"
        AUTH_REFRESH_TOKEN_EXPIRY_DURATION_MINUTES = "60"
        AUTH_COOKIE_SAME_SITE                      = "Lax"
        COOKIE_ACCESS_CONTROL_ALLOW_ORIGIN         = "https://${local.env_domain}"
      }
    }

    # Session Lambda - Validates auth cookie and returns NHS Login user info
    # CloudFront: /session/* → API Gateway → Lambda
    # CORS: handled in-code via @middy/http-cors using COOKIE_ACCESS_CONTROL_ALLOW_ORIGIN env var
    "session-lambda" = {
      description     = "Session Service - Validates auth cookie and returns user info"
      api_path_prefix = "session"
      handler         = "index.handler"
      timeout         = 30
      memory_size     = 256
      environment = {
        NODE_OPTIONS                       = "--enable-source-maps"
        ENVIRONMENT                        = local.environment
        AUTH_COOKIE_KEY_ID                 = "key"
        AUTH_COOKIE_PUBLIC_KEY_SECRET_NAME = "nhs-hometest/dev/nhs-login-private-key"
        NHS_LOGIN_BASE_ENDPOINT_URL        = "https://auth.sandpit.signin.nhs.uk"
        COOKIE_ACCESS_CONTROL_ALLOW_ORIGIN = "https://${local.env_domain}"
      }
    }

    # Order Result Lambda - Receives test results from suppliers
    # CloudFront: /result/* → API Gateway → Lambda
    "order-result-lambda" = {
      description     = "Order Result Service - Receives test results from suppliers"
      api_path_prefix = "result"
      handler         = "index.handler"
      timeout         = 30
      memory_size     = 256
      environment = {
        NODE_OPTIONS     = "--enable-source-maps"
        ENVIRONMENT      = local.environment
        RESULT_QUEUE_URL = "https://sqs.${local.aws_region}.amazonaws.com/${local.account_id}/${local.project_name}-${local.aws_account_shortname}-${local.environment}-order-results"
      }
      authorization        = "COGNITO_USER_POOLS"
      authorization_scopes = ["results/write"]
    }

    # Order Service Lambda - Creates test orders and persists to database
    # CloudFront: /order/* → API Gateway → Lambda
    "order-service-lambda" = {
      description     = "Order Service - Creates test orders and persists to database"
      api_path_prefix = "order"
      handler         = "index.handler"
      timeout         = 30
      memory_size     = 256
      environment = {
        NODE_OPTIONS              = "--enable-source-maps"
        ENVIRONMENT               = local.environment
        ORDER_PLACEMENT_QUEUE_URL = "https://sqs.${local.aws_region}.amazonaws.com/${local.account_id}/${local.project_name}-${local.environment}-order-placement"
        DB_USERNAME               = "app_user_${local.db_schema}"
        DB_ADDRESS                = dependency.aurora_postgres.outputs.cluster_endpoint
        DB_PORT                   = tostring(dependency.aurora_postgres.outputs.cluster_port)
        DB_NAME                   = dependency.aurora_postgres.outputs.cluster_database_name
        DB_SECRET_NAME            = local.app_user_secret_name
        DB_SCHEMA                 = local.db_schema
      }
    }
  }

  # API Gateway Configuration
  api_stage_name             = local.api_stage_name
  api_endpoint_type          = local.api_endpoint_type
  api_throttling_burst_limit = local.api_throttling_burst_limit
  api_throttling_rate_limit  = local.api_throttling_rate_limit

  # Domain configuration
  custom_domain_name  = local.env_domain # SPA stays at dev.hometest.service.nhs.uk (CloudFront)
  acm_certificate_arn = dependency.shared_services.outputs.acm_cloudfront_certificate_arn

  # CloudFront Configuration
  cloudfront_price_class = local.cloudfront_price_class
}
