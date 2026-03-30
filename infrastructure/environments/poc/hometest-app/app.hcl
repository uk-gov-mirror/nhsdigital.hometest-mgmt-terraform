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

  # ---------------------------------------------------------------------------
  # DOMAIN CONFIGURATION
  # Defaults produce the POC wildcard-cert pattern:
  #   SPA: dev.poc.hometest.service.nhs.uk
  #   API: api-dev.poc.hometest.service.nhs.uk
  #
  # Children that require a different pattern (e.g., dev.hometest.service.nhs.uk)
  # create a domain.hcl file in their directory — see domain.hcl.example.
  # ---------------------------------------------------------------------------
  _domain_overrides = try(read_terragrunt_config("${get_terragrunt_dir()}/domain.hcl").locals, {})

  base_domain = "${local.account_vars.locals.aws_account_shortname}.hometest.service.nhs.uk"
  env_domain  = lookup(local._domain_overrides, "env_domain", "${local.environment}.${local.base_domain}")
  api_domain  = lookup(local._domain_overrides, "api_domain", "api-${local.environment}.${local.base_domain}")

  # Certificate flags — when true the hometest-app module creates per-env certs
  # instead of relying on the shared wildcard cert from shared_services.
  create_cloudfront_certificate = lookup(local._domain_overrides, "create_cloudfront_certificate", false)
  create_api_certificate        = lookup(local._domain_overrides, "create_api_certificate", false)

  # Schema-per-environment: each env gets its own schema in the shared Aurora DB
  db_schema   = "hometest_${local.environment}"
  db_app_user = "app_user_${local.db_schema}"

  # ---------------------------------------------------------------------------
  # SECRET NAMES (environment-aware)
  # ---------------------------------------------------------------------------
  # secret_prefix                     = "nhs-hometest/${local.environment}"
  secret_prefix = "nhs-hometest/dev"
  # app_user_secret_name              = "nhs-hometest/${local.environment}/app-user-db-secret"
  preventx_client_secret_name       = "${local.secret_prefix}/preventex-dev-client-secret"
  sh24_client_secret_name           = "${local.secret_prefix}/sh24-dev-client-secret"
  nhs_login_private_key_secret_name = "${local.secret_prefix}/nhs-login-private-key"
  os_places_creds_secret_name       = "${local.secret_prefix}/os-places-creds"

  # Secrets Manager ARN prefix for building IAM policies
  secrets_arn_prefix = "arn:aws:secretsmanager:${local.aws_region}:${local.account_id}:secret"

  # ---------------------------------------------------------------------------
  # SOURCE PATHS
  # Override these in child terragrunt.hcl locals if needed
  # ---------------------------------------------------------------------------
  hometest_service_dir = trimspace(run_cmd("realpath", "${get_repo_root()}/../hometest-service"))
  scripts_dir          = "${get_repo_root()}/scripts"
  lambda_build_cache   = "${get_repo_root()}/.lambda-build-cache"
  spa_build_cache      = "${get_repo_root()}/.spa-build-cache"

  lambdas_source_dir = "${local.hometest_service_dir}/lambdas"
  lambdas_base_path  = "${local.lambdas_source_dir}/src"
  spa_source_dir     = "${local.hometest_service_dir}/ui"
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

  # NHS Login Configuration
  nhs_login_base_url                         = "https://auth.sandpit.signin.nhs.uk"
  nhs_login_client_id                        = "hometest"
  auth_session_max_duration_minutes          = "60"
  auth_access_token_expiry_duration_minutes  = "60"
  auth_refresh_token_expiry_duration_minutes = "60"
  auth_cookie_same_site                      = "Lax"
  auth_cookie_key_id                         = "key"

  # Postcode Lookup Configuration
  postcode_lookup_base_url             = "https://api.os.uk/search/places/v1"
  postcode_lookup_timeout_ms           = "5000"
  postcode_lookup_max_retries          = "3"
  postcode_lookup_retry_delay_ms       = "1000"
  postcode_lookup_retry_backoff_factor = "2"
  use_stub_postcode_client             = false

  # Commonly used derived values
  spa_origin = "https://${local.env_domain}"

  sqs_prefix                = "https://sqs.${local.aws_region}.amazonaws.com/${local.account_id}/${local.project_name}-${local.aws_account_shortname}-${local.environment}"
  order_placement_queue_url = "${local.sqs_prefix}-order-placement"

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
  # Runs under hometest-service mise env so the correct Node.js version is used
  before_hook "build_lambdas" {
    commands = ["plan",
    "apply"]
    execute = [
      "bash", "-c",
      "mise exec -C '${local.hometest_service_dir}' -- '${local.scripts_dir}/build-lambdas.sh' '${local.lambdas_source_dir}' '${local.lambda_build_cache}'"
    ]
  }

  # Build SPA before apply (only rebuilds when source or backend URL changes)
  # Uses scripts/build-spa.sh which content-hashes source + NEXT_PUBLIC_BACKEND_URL
  # Runs under hometest-service mise env so the correct Node.js version is used
  before_hook "build_spa" {
    commands = ["plan", "apply"]
    execute = [
      "bash", "-c",
      "mise exec -C '${local.hometest_service_dir}' -- '${local.scripts_dir}/build-spa.sh' '${local.spa_source_dir}' '${local.spa_build_cache}' 'https://${local.api_domain}' '${local.spa_type}'"
    ]
  }

  # Upload SPA to S3 after terraform creates the bucket, then invalidate CloudFront.
  # Uses scripts/upload-spa.sh with type-specific caching (Next.js / Vite).
  # Bucket name and CloudFront ID are read from terraform outputs at runtime.
  after_hook "upload_spa" {
    commands     = ["apply"]
    run_on_error = false
    execute = [
      "bash", "-c",
      <<-EOF
        SPA_BUCKET=$(terraform output -raw spa_bucket_id 2>/dev/null || echo "")
        CLOUDFRONT_ID=$(terraform output -raw cloudfront_distribution_id 2>/dev/null || echo "")
        if [[ -n "$SPA_BUCKET" ]]; then
          CF_FLAG=""
          if [[ -n "$CLOUDFRONT_ID" ]]; then
            CF_FLAG="--cloudfront-id $CLOUDFRONT_ID"
          fi
          "${local.scripts_dir}/upload-spa.sh" "${local.spa_dist_dir}" "$SPA_BUCKET" \
            --spa-type "${local.spa_type}" \
            --region "${local.aws_region}" \
            --spa-source-dir "${local.spa_source_dir}" \
            $CF_FLAG
        else
          echo "Could not determine SPA bucket from terraform outputs, skipping upload..."
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
  waf_regional_arn     = dependency.shared_services.outputs.waf_regional_arn

  # Lambda Configuration
  enable_vpc_access  = true
  lambda_runtime     = local.lambda_runtime
  lambda_timeout     = local.lambda_timeout
  lambda_memory_size = local.lambda_memory_size
  log_retention_days = local.log_retention_days

  # IAM Permissions - Grant Lambda access to secrets
  # Note: AWS Secrets Manager ARNs have a random suffix, use -* wildcard to match
  lambda_secrets_arns = [
    "${local.secrets_arn_prefix}:${local.preventx_client_secret_name}-*",
    "${local.secrets_arn_prefix}:${local.sh24_client_secret_name}-*",
    "${local.secrets_arn_prefix}:${local.nhs_login_private_key_secret_name}-*",
    "${local.secrets_arn_prefix}:${local.os_places_creds_secret_name}-*"
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
  authorized_api_prefixes = ["result", "test-order-status"]

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
      timeout         = local.lambda_timeout
      memory_size     = local.lambda_memory_size
      environment = {
        NODE_OPTIONS = "--enable-source-maps"
        ENVIRONMENT  = local.environment
        ALLOW_ORIGIN = local.spa_origin
        DB_USERNAME  = local.db_app_user
        DB_ADDRESS   = dependency.aurora_postgres.outputs.cluster_endpoint
        DB_PORT      = tostring(dependency.aurora_postgres.outputs.cluster_port)
        DB_NAME      = dependency.aurora_postgres.outputs.cluster_database_name
        DB_SCHEMA    = local.db_schema
        USE_IAM_AUTH = "true"
        DB_REGION    = local.aws_region
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
        NODE_OPTIONS = "--enable-source-maps"
        ENVIRONMENT  = local.environment
        DB_USERNAME  = local.db_app_user
        DB_ADDRESS   = dependency.aurora_postgres.outputs.cluster_endpoint
        DB_PORT      = tostring(dependency.aurora_postgres.outputs.cluster_port)
        DB_NAME      = dependency.aurora_postgres.outputs.cluster_database_name
        DB_SCHEMA    = local.db_schema
        USE_IAM_AUTH = "true"
        DB_REGION    = local.aws_region
      }
    }

    # Login Lambda - NHS Login authentication
    # CloudFront: /login/* → API Gateway → Lambda
    # CORS: handled in-code via @middy/http-cors using COOKIE_ACCESS_CONTROL_ALLOW_ORIGIN env var
    "login-lambda" = {
      description     = "Login Service - NHS Login authentication"
      api_path_prefix = "login"
      handler         = "index.handler"
      timeout         = local.lambda_timeout
      memory_size     = local.lambda_memory_size
      environment = {
        NODE_OPTIONS                               = "--enable-source-maps"
        ENVIRONMENT                                = local.environment
        NHS_LOGIN_BASE_ENDPOINT_URL                = local.nhs_login_base_url
        NHS_LOGIN_CLIENT_ID                        = local.nhs_login_client_id
        NHS_LOGIN_REDIRECT_URL                     = "${local.spa_origin}/callback"
        NHS_LOGIN_PRIVATE_KEY_SECRET_NAME          = local.nhs_login_private_key_secret_name
        AUTH_SESSION_MAX_DURATION_MINUTES          = local.auth_session_max_duration_minutes
        AUTH_ACCESS_TOKEN_EXPIRY_DURATION_MINUTES  = local.auth_access_token_expiry_duration_minutes
        AUTH_REFRESH_TOKEN_EXPIRY_DURATION_MINUTES = local.auth_refresh_token_expiry_duration_minutes
        AUTH_COOKIE_SAME_SITE                      = local.auth_cookie_same_site
        COOKIE_ACCESS_CONTROL_ALLOW_ORIGIN         = local.spa_origin
      }
    }

    # Session Lambda - Validates auth cookie and returns NHS Login user info
    # CloudFront: /session/* → API Gateway → Lambda
    # CORS: handled in-code via @middy/http-cors using COOKIE_ACCESS_CONTROL_ALLOW_ORIGIN env var
    "session-lambda" = {
      description     = "Session Service - Validates auth cookie and returns user info"
      api_path_prefix = "session"
      handler         = "index.handler"
      timeout         = local.lambda_timeout
      memory_size     = local.lambda_memory_size
      environment = {
        NODE_OPTIONS                       = "--enable-source-maps"
        ENVIRONMENT                        = local.environment
        AUTH_COOKIE_KEY_ID                 = local.auth_cookie_key_id
        AUTH_COOKIE_PUBLIC_KEY_SECRET_NAME = local.nhs_login_private_key_secret_name
        NHS_LOGIN_BASE_ENDPOINT_URL        = local.nhs_login_base_url
        COOKIE_ACCESS_CONTROL_ALLOW_ORIGIN = local.spa_origin
      }
    }

    # Order Result Lambda - Receives test results from suppliers
    # CloudFront: /result/* → API Gateway → Lambda
    "order-result-lambda" = {
      description     = "Order Result Service - Receives test results from suppliers"
      api_path_prefix = "result"
      handler         = "index.handler"
      timeout         = local.lambda_timeout
      memory_size     = local.lambda_memory_size
      environment = {
        NODE_OPTIONS = "--enable-source-maps"
        ENVIRONMENT  = local.environment
        DB_USERNAME  = local.db_app_user
        DB_ADDRESS   = dependency.aurora_postgres.outputs.cluster_endpoint
        DB_PORT      = tostring(dependency.aurora_postgres.outputs.cluster_port)
        DB_NAME      = dependency.aurora_postgres.outputs.cluster_database_name
        DB_SCHEMA    = local.db_schema
        USE_IAM_AUTH = "true"
        DB_REGION    = local.aws_region
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
      http_method     = "POST"
      timeout         = local.lambda_timeout
      memory_size     = local.lambda_memory_size
      environment = {
        NODE_OPTIONS              = "--enable-source-maps"
        ENVIRONMENT               = local.environment
        ALLOW_ORIGIN              = local.spa_origin
        ORDER_PLACEMENT_QUEUE_URL = local.order_placement_queue_url
        DB_USERNAME               = local.db_app_user
        DB_ADDRESS                = dependency.aurora_postgres.outputs.cluster_endpoint
        DB_PORT                   = tostring(dependency.aurora_postgres.outputs.cluster_port)
        DB_NAME                   = dependency.aurora_postgres.outputs.cluster_database_name
        DB_SCHEMA                 = local.db_schema
        USE_IAM_AUTH              = "true"
        DB_REGION                 = local.aws_region
      }
    }

    # Get Order Lambda - Retrieves order details from database
    # CloudFront: /order/* (GET) → API Gateway → Lambda
    "get-order-lambda" = {
      description = "Get Order Service - Retrieves order details from database"
      # /order in local env, changed because API GW v1 doesn't support overlapping path prefixes (e.g., /order and /order/status) — can be simplified to /order in non-local envs
      api_path_prefix = "get-order"
      handler         = "index.handler"
      http_method     = "GET"
      timeout         = local.lambda_timeout
      memory_size     = local.lambda_memory_size
      environment = {
        NODE_OPTIONS = "--enable-source-maps"
        ENVIRONMENT  = local.environment
        ALLOW_ORIGIN = local.spa_origin
        DB_USERNAME  = local.db_app_user
        DB_ADDRESS   = dependency.aurora_postgres.outputs.cluster_endpoint
        DB_PORT      = tostring(dependency.aurora_postgres.outputs.cluster_port)
        DB_NAME      = dependency.aurora_postgres.outputs.cluster_database_name
        DB_SCHEMA    = local.db_schema
        USE_IAM_AUTH = "true"
        DB_REGION    = local.aws_region
      }
    }

    # Get Results Lambda - Retrieves test results from database
    # CloudFront: /results/* (GET) → API Gateway → Lambda
    "get-results-lambda" = {
      description     = "Get Results Service - Retrieves test results from database"
      api_path_prefix = "results"
      handler         = "index.handler"
      http_method     = "GET"
      timeout         = local.lambda_timeout
      memory_size     = local.lambda_memory_size
      environment = {
        NODE_OPTIONS = "--enable-source-maps"
        ENVIRONMENT  = local.environment
        ALLOW_ORIGIN = local.spa_origin
        DB_USERNAME  = local.db_app_user
        DB_ADDRESS   = dependency.aurora_postgres.outputs.cluster_endpoint
        DB_PORT      = tostring(dependency.aurora_postgres.outputs.cluster_port)
        DB_NAME      = dependency.aurora_postgres.outputs.cluster_database_name
        DB_SCHEMA    = local.db_schema
        USE_IAM_AUTH = "true"
        DB_REGION    = local.aws_region
      }
    }

    # Order Status Lambda - Updates order status
    # CloudFront: /test-order-status/* (POST) → API Gateway → Lambda
    "order-status-lambda" = {
      description = "Order Status Service - Updates order status"
      # test-order/status in local env, changed because API GW v1 doesn't support overlapping path prefixes (e.g., /order and /order/status) — can be simplified to /order-status in non-local envs
      api_path_prefix = "test-order-status"
      handler         = "index.handler"
      http_method     = "POST"
      timeout         = local.lambda_timeout
      memory_size     = local.lambda_memory_size
      environment = {
        NODE_OPTIONS = "--enable-source-maps"
        ENVIRONMENT  = local.environment
        ALLOW_ORIGIN = local.spa_origin
        DB_USERNAME  = local.db_app_user
        DB_ADDRESS   = dependency.aurora_postgres.outputs.cluster_endpoint
        DB_PORT      = tostring(dependency.aurora_postgres.outputs.cluster_port)
        DB_NAME      = dependency.aurora_postgres.outputs.cluster_database_name
        DB_SCHEMA    = local.db_schema
        USE_IAM_AUTH = "true"
        DB_REGION    = local.aws_region
      }

      authorization        = "COGNITO_USER_POOLS"
      authorization_scopes = ["orders/write"]
    }

    # Postcode Lookup Lambda - Looks up addresses by postcode via OS Places API
    # CloudFront: /postcode-lookup/* (GET) → API Gateway → Lambda
    "postcode-lookup-lambda" = {
      description     = "Postcode Lookup Service - Address lookup via OS Places API"
      api_path_prefix = "postcode-lookup"
      handler         = "index.handler"
      http_method     = "GET"
      timeout         = local.lambda_timeout
      memory_size     = local.lambda_memory_size
      environment = {
        NODE_OPTIONS                            = "--enable-source-maps"
        ENVIRONMENT                             = local.environment
        ALLOW_ORIGIN                            = local.spa_origin
        POSTCODE_LOOKUP_CREDENTIALS_SECRET_NAME = local.os_places_creds_secret_name
        POSTCODE_LOOKUP_BASE_URL                = local.postcode_lookup_base_url
        POSTCODE_LOOKUP_TIMEOUT_MS              = local.postcode_lookup_timeout_ms
        POSTCODE_LOOKUP_MAX_RETRIES             = local.postcode_lookup_max_retries
        POSTCODE_LOOKUP_RETRY_DELAY_MS          = local.postcode_lookup_retry_delay_ms
        POSTCODE_LOOKUP_RETRY_BACKOFF_FACTOR    = local.postcode_lookup_retry_backoff_factor
        USE_STUB_POSTCODE_CLIENT                = local.use_stub_postcode_client
      }
    }
  }

  # API Gateway Configuration
  api_stage_name             = local.api_stage_name
  api_endpoint_type          = local.api_endpoint_type
  api_throttling_burst_limit = local.api_throttling_burst_limit
  api_throttling_rate_limit  = local.api_throttling_rate_limit

  # Domain configuration
  custom_domain_name  = local.env_domain
  acm_certificate_arn = dependency.shared_services.outputs.acm_cloudfront_certificate_arn

  api_custom_domain_name       = local.api_domain
  acm_regional_certificate_arn = dependency.shared_services.outputs.acm_regional_certificate_arn

  # CORS — API Gateway OPTIONS responses and gateway error responses use this origin.
  # Must match the SPA domain exactly (credentials require a specific origin, not '*').
  cors_allowed_origin = local.spa_origin

  # Per-environment certificate creation (set via domain.hcl in child dirs)
  create_cloudfront_certificate = local.create_cloudfront_certificate
  create_api_certificate        = local.create_api_certificate

  # CloudFront Configuration
  cloudfront_price_class = local.cloudfront_price_class
}
