# ---------------------------------------------------------------------------------------------------------------------
# COMMON TERRAGRUNT CONFIGURATION FOR HOMETEST-APP
# Location: _envcommon/hometest-app.hcl
#
# Shared configuration for all environments (dev, dev-mikmio, etc.) under poc/hometest-app/.
# Environment-specific app/terragrunt.hcl files include this and override only what's needed.
#
# Expected directory layout per environment:
#   poc/hometest-app/{env}/
#   ├── env.hcl                  (environment name + optional domain/wiremock overrides)
#   ├── app/
#   │   └── terragrunt.hcl       (includes this file)
#   └── lambda-goose-migrator/
#       └── terragrunt.hcl
#
# Environment name is derived from the parent directory name (dirname of get_terragrunt_dir()).
#
# Usage in child app/terragrunt.hcl:
#   include "app" {
#     path           = find_in_parent_folders("_envcommon/hometest-app.hcl")
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
  account_vars     = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  global_vars      = read_terragrunt_config(find_in_parent_folders("_envcommon/all.hcl"))
  account_app_vars = read_terragrunt_config(find_in_parent_folders("app.hcl"))

  # Environment derived from parent directory name (e.g., dev/, dev-mikmio/)
  # get_terragrunt_dir() returns {env}/app/, so dirname gives {env}/
  _env_dir    = dirname(get_terragrunt_dir())
  environment = basename(local._env_dir)

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
  # To override, add domain locals (env_domain, api_domain, create_*_certificate)
  # directly in the environment's env.hcl file.
  # ---------------------------------------------------------------------------

  # Read per-environment config from env.hcl in the parent (environment) directory.
  # env.hcl carries the environment name, domain overrides, and feature flags (e.g., wiremock).
  _env_flags                 = try(read_terragrunt_config("${local._env_dir}/env.hcl").locals, {})
  _domain_overrides          = local._env_flags
  enable_wiremock            = lookup(local._env_flags, "enable_wiremock", false)
  wiremock_bypass_waf        = lookup(local._env_flags, "wiremock_bypass_waf", false)
  wiremock_scheduled_scaling = lookup(local._env_flags, "wiremock_scheduled_scaling", false)
  wiremock_use_spot          = lookup(local._env_flags, "wiremock_use_spot", true)
  wiremock_cpu               = lookup(local._env_flags, "wiremock_cpu", 256)
  wiremock_memory            = lookup(local._env_flags, "wiremock_memory", 512)

  # Alerts — opt-in per environment via env.hcl (default: false)
  enable_alerts = lookup(local._env_flags, "enable_alerts", false)

  # mTLS on the API Gateway custom domain — opt-in per environment.
  # WARNING: enabling mTLS on the browser-facing API domain will break SPA CORS
  # because browsers never send client certificates on preflight OPTIONS requests.
  # Only enable for domains used exclusively by machine-to-machine traffic.
  enable_api_mtls = lookup(local._env_flags, "enable_api_mtls", false)

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
  # SECRET NAMES (from account-level app.hcl, overridable per-environment)
  # ---------------------------------------------------------------------------
  secret_prefix                     = local.account_app_vars.locals.secret_prefix
  preventx_client_secret_name       = local.account_app_vars.locals.preventx_client_secret_name
  sh24_client_secret_name           = local.account_app_vars.locals.sh24_client_secret_name
  nhs_login_private_key_secret_name = local.account_app_vars.locals.nhs_login_private_key_secret_name
  os_places_creds_secret_name       = local.account_app_vars.locals.os_places_creds_secret_name

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
  lambda_node_env    = "production" # "production" = minified, "development" = unminified + sourcemaps

  # API Gateway Defaults
  api_stage_name             = "v1"
  api_endpoint_type          = "REGIONAL"
  api_throttling_burst_limit = 1000
  api_throttling_rate_limit  = 2000

  # CloudFront Defaults
  cloudfront_price_class = "PriceClass_100"

  # NHS Login Configuration (from account-level app.hcl)
  nhs_login_base_url                         = local.account_app_vars.locals.nhs_login_base_url
  nhs_login_authorize_url                    = "${local.nhs_login_base_url}/authorize"
  nhs_login_client_id                        = local.account_app_vars.locals.nhs_login_client_id
  auth_session_max_duration_minutes          = "60"
  auth_access_token_expiry_duration_minutes  = "60"
  auth_refresh_token_expiry_duration_minutes = "60"
  auth_cookie_same_site                      = "Lax"
  auth_cookie_key_id                         = "key"

  # ---------------------------------------------------------------------------
  # SPA BUILD: NHS Login authorize URL and WireMock auth flag
  # When enable_wiremock = true the SPA uses the per-environment WireMock domain
  # as the NHS Login stub and sets NEXT_PUBLIC_USE_WIREMOCK_AUTH=true.
  # When false, the real NHS Login sandpit is used.
  # ---------------------------------------------------------------------------
  wiremock_domain             = "wiremock-${local.environment}.${local.base_domain}"
  wiremock_base_url_for_spa   = "https://${local.wiremock_domain}"
  spa_nhs_login_authorize_url = local.enable_wiremock ? "${local.wiremock_base_url_for_spa}/authorize" : local.nhs_login_authorize_url
  use_wiremock_auth           = local.enable_wiremock

  # NHS Login base URL used by lambdas (login-lambda, session-lambda):
  # when WireMock is enabled, lambdas must validate tokens against the WireMock JWKS endpoint
  # so the issuer in the JWT matches the URL the lambda verifies against.
  nhs_login_lambda_base_url = local.enable_wiremock ? local.wiremock_base_url_for_spa : local.nhs_login_base_url

  # JWKS URI for the login-lambda JwksClient.
  # When WireMock is enabled, the lambda is in a VPC and must reach WireMock via internal
  # service discovery (bypassing the public ALB/WAF) to avoid a 403 Forbidden on JWKS fetch.
  # The ECS cluster is deployed under poc/core/ecs/ with environment="core", so its
  # service discovery namespace follows: ecs.<project>-<account>-core.local
  # The WireMock service itself is named wiremock-<env> (e.g. wiremock-uat).
  # When disabled, the lambda derives the URI from nhs_login_lambda_base_url automatically.
  _ecs_service_discovery_namespace = "ecs.${local.project_name}-${local.aws_account_shortname}-core.local"
  nhs_login_jwks_uri               = local.enable_wiremock ? "http://wiremock-${local.environment}.${local._ecs_service_discovery_namespace}:8080/.well-known/jwks.json" : ""

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
  notify_messages_queue_url = "${local.sqs_prefix}-notify-messages"

  # ECS dependency — only enabled when the core/ecs stack exists (needed for WireMock)
  _ecs_enabled = fileexists("${local._env_dir}/../../core/ecs/terragrunt.hcl")

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
  # Build and package artifacts locally BEFORE terraform runs.
  # All configuration is passed via environment variables.
  # Scripts live in scripts/ and are run under hometest-service's mise env.
  # ---------------------------------------------------------------------------

  before_hook "build_lambdas" {
    commands = ["plan", "apply"]
    execute = [
      "bash", "-c",
      <<-EOF
        cd '${local.hometest_service_dir}' && \
        LAMBDAS_SOURCE_DIR='${local.lambdas_source_dir}' \
        LAMBDAS_CACHE_DIR='${local.lambda_build_cache}' \
        NODE_ENV='${local.lambda_node_env}' \
        mise exec -- '${local.scripts_dir}/build-lambdas.sh'
      EOF
    ]
  }

  before_hook "build_spa" {
    commands = ["plan", "apply"]
    execute = [
      "bash", "-c",
      <<-EOF
        cd '${local.hometest_service_dir}' && \
        SPA_SOURCE_DIR='${local.spa_source_dir}' \
        SPA_CACHE_DIR='${local.spa_build_cache}' \
        SPA_TYPE='${local.spa_type}' \
        NEXT_PUBLIC_BACKEND_URL='https://${local.api_domain}' \
        NEXT_PUBLIC_NHS_LOGIN_AUTHORIZE_URL='${local.spa_nhs_login_authorize_url}' \
        NEXT_PUBLIC_USE_WIREMOCK_AUTH='${local.use_wiremock_auth}' \
        mise exec -- '${local.scripts_dir}/build-spa.sh'
      EOF
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
          cd '${local.hometest_service_dir}' && \
          mise exec -- '${local.scripts_dir}/upload-spa.sh' '${local.spa_dist_dir}' "$SPA_BUCKET" \
            --spa-type '${local.spa_type}' \
            --region '${local.aws_region}' \
            --spa-source-dir '${local.spa_source_dir}' \
            $CF_FLAG
        else
          echo "Could not determine SPA bucket from terraform outputs, skipping upload..."
        fi
      EOF
    ]
  }

  # Push WireMock stubs after apply when WireMock is enabled for the environment.
  # Runs `npm run wiremock:push` from hometest-service/tests with the correct base URL.
  after_hook "push_wiremock_stubs" {
    commands     = ["apply"]
    run_on_error = false
    execute = [
      "bash", "-c",
      <<-EOF
        if [[ "${local.enable_wiremock}" == "true" ]]; then
          echo "Pushing WireMock stubs to ${local.wiremock_base_url_for_spa} ..."
          cd '${local.hometest_service_dir}/tests' && \
          WIREMOCK_BASE_URL='${local.wiremock_base_url_for_spa}' \
          mise exec -- npm run wiremock:push
        else
          echo "WireMock not enabled for this environment, skipping stub push."
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
  config_path = "${get_terragrunt_dir()}/../../../core/network"

  mock_outputs = {
    route53_zone_id              = "Z0123456789ABCDEFGHIJ"
    vpc_id                       = "vpc-mock12345"
    private_subnet_ids           = ["subnet-mock1", "subnet-mock2", "subnet-mock3"]
    public_subnet_ids            = ["subnet-pub-mock1", "subnet-pub-mock2", "subnet-pub-mock3"]
    lambda_security_group_id     = "sg-mock12345"
    lambda_rds_security_group_id = "sg-mock67890"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

dependency "shared_services" {
  config_path = "${get_terragrunt_dir()}/../../../core/shared_services"

  mock_outputs = {
    kms_key_arn                     = "arn:aws:kms:eu-west-2:123456789012:key/mock-key-id"
    pii_data_kms_key_arn            = "arn:aws:kms:eu-west-2:123456789012:key/mock-pii-key-id"
    sns_alerts_topic_arn            = "arn:aws:sns:eu-west-2:123456789012:mock-alerts-topic"
    sns_alerts_critical_topic_arn   = "arn:aws:sns:eu-west-2:123456789012:mock-alerts-critical-topic"
    waf_regional_arn                = "arn:aws:wafv2:eu-west-2:123456789012:regional/webacl/mock/mock-id"
    waf_cloudfront_arn              = "arn:aws:wafv2:us-east-1:123456789012:global/webacl/mock/mock-id"
    acm_regional_certificate_arn    = "arn:aws:acm:eu-west-2:123456789012:certificate/mock-cert"
    acm_cloudfront_certificate_arn  = "arn:aws:acm:us-east-1:123456789012:certificate/mock-cert"
    deployment_artifacts_bucket_id  = "mock-deployment-bucket"
    deployment_artifacts_bucket_arn = "arn:aws:s3:::mock-deployment-bucket"
    api_config_secret_arn           = "arn:aws:secretsmanager:eu-west-2:123456789012:secret:mock-secret"
    api_config_secret_name          = "mock/secret/name"
    cognito_user_pool_arn           = "arn:aws:cognito-idp:eu-west-2:123456789012:userpool/eu-west-2_mockpool"
    mtls_truststore_uri             = null
    mtls_truststore_version         = null
  }
  mock_outputs_merge_with_state           = true
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

dependency "aurora_postgres" {
  config_path = "${get_terragrunt_dir()}/../../../core/aurora-postgres"

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

dependency "ecs" {
  enabled     = local._ecs_enabled
  config_path = "${get_terragrunt_dir()}/../../../core/ecs"

  mock_outputs = {
    cluster_arn                      = "arn:aws:ecs:eu-west-2:123456789012:cluster/mock-ecs-cluster"
    cluster_name                     = "mock-ecs-cluster"
    service_discovery_namespace_id   = "ns-mock1234567890"
    service_discovery_namespace_name = "ecs.mock.local"
    alb_arn                          = "arn:aws:elasticloadbalancing:eu-west-2:123456789012:loadbalancer/app/mock-alb/1234567890"
    alb_dns_name                     = "mock-alb-123456.eu-west-2.elb.amazonaws.com"
    alb_zone_id                      = "ZHURV8PSTC4K8"
    alb_security_group_id            = "sg-mock-alb-12345"
    alb_https_listener_arn           = "arn:aws:elasticloadbalancing:eu-west-2:123456789012:listener/app/mock-alb/1234567890/abcdef"
  }
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
  kms_key_arn                   = dependency.shared_services.outputs.kms_key_arn
  pii_data_kms_key_arn          = dependency.shared_services.outputs.pii_data_kms_key_arn
  sns_alerts_topic_arn          = local.enable_alerts ? dependency.shared_services.outputs.sns_alerts_topic_arn : null
  sns_alerts_critical_topic_arn = local.enable_alerts ? dependency.shared_services.outputs.sns_alerts_critical_topic_arn : null

  # OK actions — set to true for prod to get notified when alarms recover
  enable_ok_actions = false

  waf_cloudfront_arn = dependency.shared_services.outputs.waf_cloudfront_arn
  waf_regional_arn   = dependency.shared_services.outputs.waf_regional_arn

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
    # CORS: handled in-code via @middy/http-cors using ALLOW_ORIGIN env var
    "login-lambda" = {
      description     = "Login Service - NHS Login authentication"
      api_path_prefix = "login"
      handler         = "index.handler"
      timeout         = local.lambda_timeout
      memory_size     = local.lambda_memory_size
      environment = {
        NODE_OPTIONS                               = "--enable-source-maps"
        ENVIRONMENT                                = local.environment
        ALLOW_ORIGIN                               = local.spa_origin
        NHS_LOGIN_BASE_ENDPOINT_URL                = local.nhs_login_lambda_base_url
        NHS_LOGIN_JWKS_URI                         = local.nhs_login_jwks_uri
        NHS_LOGIN_CLIENT_ID                        = local.nhs_login_client_id
        NHS_LOGIN_REDIRECT_URL                     = "${local.spa_origin}/callback"
        NHS_LOGIN_PRIVATE_KEY_SECRET_NAME          = local.nhs_login_private_key_secret_name
        AUTH_SESSION_MAX_DURATION_MINUTES          = local.auth_session_max_duration_minutes
        AUTH_ACCESS_TOKEN_EXPIRY_DURATION_MINUTES  = local.auth_access_token_expiry_duration_minutes
        AUTH_REFRESH_TOKEN_EXPIRY_DURATION_MINUTES = local.auth_refresh_token_expiry_duration_minutes
        AUTH_COOKIE_SAME_SITE                      = local.auth_cookie_same_site
        # COOKIE_ACCESS_CONTROL_ALLOW_ORIGIN         = local.spa_origin
      }
    }

    # Session Lambda - Validates auth cookie and returns NHS Login user info
    # CloudFront: /session/* → API Gateway → Lambda
    # CORS: handled in-code via @middy/http-cors using ALLOW_ORIGIN env var
    "session-lambda" = {
      description     = "Session Service - Validates auth cookie and returns user info"
      api_path_prefix = "session"
      handler         = "index.handler"
      timeout         = local.lambda_timeout
      memory_size     = local.lambda_memory_size
      environment = {
        NODE_OPTIONS                       = "--enable-source-maps"
        ENVIRONMENT                        = local.environment
        ALLOW_ORIGIN                       = local.spa_origin
        AUTH_COOKIE_KEY_ID                 = local.auth_cookie_key_id
        AUTH_COOKIE_PUBLIC_KEY_SECRET_NAME = local.nhs_login_private_key_secret_name
        NHS_LOGIN_BASE_ENDPOINT_URL        = local.nhs_login_lambda_base_url
        # COOKIE_ACCESS_CONTROL_ALLOW_ORIGIN = local.spa_origin
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
        NODE_OPTIONS              = "--enable-source-maps"
        ENVIRONMENT               = local.environment
        DB_USERNAME               = local.db_app_user
        DB_ADDRESS                = dependency.aurora_postgres.outputs.cluster_endpoint
        DB_PORT                   = tostring(dependency.aurora_postgres.outputs.cluster_port)
        DB_NAME                   = dependency.aurora_postgres.outputs.cluster_database_name
        DB_SCHEMA                 = local.db_schema
        USE_IAM_AUTH              = "true"
        DB_REGION                 = local.aws_region
        NOTIFY_MESSAGES_QUEUE_URL = local.notify_messages_queue_url
        HOME_TEST_BASE_URL        = local.spa_origin
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
        NODE_OPTIONS              = "--enable-source-maps"
        ENVIRONMENT               = local.environment
        ALLOW_ORIGIN              = local.spa_origin
        DB_USERNAME               = local.db_app_user
        DB_ADDRESS                = dependency.aurora_postgres.outputs.cluster_endpoint
        DB_PORT                   = tostring(dependency.aurora_postgres.outputs.cluster_port)
        DB_NAME                   = dependency.aurora_postgres.outputs.cluster_database_name
        DB_SCHEMA                 = local.db_schema
        USE_IAM_AUTH              = "true"
        DB_REGION                 = local.aws_region
        NOTIFY_MESSAGES_QUEUE_URL = local.notify_messages_queue_url
        HOME_TEST_BASE_URL        = local.spa_origin
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

  # Mutual TLS (mTLS) — only wired when enable_api_mtls = true in env.hcl.
  # Disabled by default: the SPA makes browser requests to this API domain,
  # and browsers cannot satisfy mTLS client-certificate requirements on CORS
  # preflight (OPTIONS) requests, causing "CORS request did not succeed".
  api_mutual_tls_truststore_uri     = local.enable_api_mtls ? dependency.shared_services.outputs.mtls_truststore_uri : null
  api_mutual_tls_truststore_version = local.enable_api_mtls ? dependency.shared_services.outputs.mtls_truststore_version : null

  # CORS — API Gateway OPTIONS responses and gateway error responses use this origin.
  # Must match the SPA domain exactly (credentials require a specific origin, not '*').
  cors_allowed_origin = local.spa_origin

  # Per-environment certificate creation (set via domain.hcl in child dirs)
  create_cloudfront_certificate = local.create_cloudfront_certificate
  create_api_certificate        = local.create_api_certificate

  # CloudFront Configuration
  cloudfront_price_class = local.cloudfront_price_class

  # ---------------------------------------------------------------------------
  # WireMock (ECS Fargate) — routes via shared ALB with host-based rules
  # Disabled by default — enable per-environment in child env.hcl
  # Used for Playwright E2E tests and stubbing 3rd-party APIs in dev envs
  # ---------------------------------------------------------------------------
  enable_wiremock                         = local.enable_wiremock
  wiremock_bypass_waf                     = local.wiremock_bypass_waf
  wiremock_ecs_cluster_arn                = dependency.ecs.outputs.cluster_arn
  wiremock_subnet_ids                     = dependency.network.outputs.private_subnet_ids
  wiremock_public_subnet_ids              = local.wiremock_bypass_waf ? dependency.network.outputs.public_subnet_ids : []
  wiremock_alb_https_listener_arn         = dependency.ecs.outputs.alb_https_listener_arn
  wiremock_alb_security_group_id          = dependency.ecs.outputs.alb_security_group_id
  wiremock_alb_dns_name                   = dependency.ecs.outputs.alb_dns_name
  wiremock_alb_zone_id                    = dependency.ecs.outputs.alb_zone_id
  wiremock_service_discovery_namespace_id = dependency.ecs.outputs.service_discovery_namespace_id
  wiremock_domain_name                    = local.wiremock_domain
  wiremock_scheduled_scaling              = local.wiremock_scheduled_scaling
  wiremock_ecs_cluster_name               = local.wiremock_scheduled_scaling ? dependency.ecs.outputs.cluster_name : null
  wiremock_use_spot                       = local.wiremock_use_spot
  wiremock_cpu                            = local.wiremock_cpu
  wiremock_memory                         = local.wiremock_memory
}
