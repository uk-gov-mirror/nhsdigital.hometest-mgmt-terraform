# ---------------------------------------------------------------------------------------------------------------------
# COMMON TERRAGRUNT CONFIGURATION FOR GOOSE MIGRATOR
# Location: _envcommon/goose-migrator.hcl
#
# Shared configuration for database migrations across all environments (dev, uat, prod).
# Runs Goose migrations for schema-per-environment in the shared Aurora cluster.
# Creates a schema-scoped app_user with credentials stored in Secrets Manager.
#
# Environment name is derived automatically from the parent directory name (e.g., dev/, uat/).
#
# Usage in child terragrunt.hcl:
#   include "goose-migrator" {
#     path           = find_in_parent_folders("_envcommon/goose-migrator.hcl")
#     expose         = true
#     merge_strategy = "deep"
#   }
#
# To add environment-specific overrides, define an inputs block in the child terragrunt.hcl.
# ---------------------------------------------------------------------------------------------------------------------

# ---------------------------------------------------------------------------------------------------------------------
# LOCALS - Common configuration values
# ---------------------------------------------------------------------------------------------------------------------

locals {
  # Parent directory is the environment name (e.g., dev, uat)
  environment = basename(dirname(get_terragrunt_dir()))

  # Schema name derived from environment: hometest_dev, hometest_uat, etc.
  db_schema = "hometest_${local.environment}"

  # Secrets Manager path for app user credentials
  app_user_secret_name = "nhs-hometest/${local.environment}/app-user-db-secret"

  # Resolved paths
  scripts_dir          = "${get_repo_root()}/scripts"
  migrator_build_cache = "${get_repo_root()}/.migrator-build-cache"

  # Path to service directory
  hometest_service_dir = trimspace(run_cmd("realpath", "${get_repo_root()}/../hometest-service"))

}

# ---------------------------------------------------------------------------------------------------------------------
# TERRAFORM SOURCE
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/infrastructure//src/lambda-goose-migrator"

  # ---------------------------------------------------------------------------
  # BUILD HOOK — compile the Go binary and package the zip before plan/apply
  # ---------------------------------------------------------------------------

  before_hook "build_goose_migrator" {
    commands = ["plan", "apply"]
    execute = [
      "bash", "-c",
      <<-EOF
        cd '${local.hometest_service_dir}' && \
        LAMBDAS_SOURCE_DIR='${local.hometest_service_dir}/lambdas' \
        MIGRATOR_CACHE_DIR='${local.migrator_build_cache}' \
        mise exec -- '${local.scripts_dir}/build-goose-migrator.sh'
      EOF
    ]
  }

  # ---------------------------------------------------------------------------
  # HOOKS — invoke the goose-migrator Lambda automatically after apply / before destroy
  #
  # These hooks mean you can simply run:
  #   cd poc/hometest-app/<env>/lambda-goose-migrator
  #   terragrunt apply    # deploys Lambda then runs migrations
  #   terragrunt destroy  # tears down schema/user then destroys Lambda infra
  #
  # The helper script works both locally and in CI (writes GITHUB_STEP_SUMMARY
  # when that variable is set).
  #
  # SKIPPING (local):  export SKIP_MIGRATOR=true before running terragrunt.
  #                    This deploys/destroys the Lambda infrastructure but skips
  #                    the Lambda invocation (no migrations or teardown run).
  # SKIPPING (CI):     Set the 'skip_migrator' input on the workflow dispatch.
  #                    This bypasses the entire deploy-migrator job.
  # ---------------------------------------------------------------------------

  # After a successful apply, invoke the Lambda to run migrations
  after_hook "invoke_migrate" {
    commands     = ["apply"]
    run_on_error = false
    execute = [
      "bash", "-c",
      <<-EOF
        FUNCTION_NAME=$(terraform output -raw function_name 2>/dev/null || echo "")
        "${local.scripts_dir}/invoke-goose-migrator.sh" \
          "$FUNCTION_NAME" \
          "migrate" \
          "${local.environment}"
      EOF
    ]
  }

  # Before destroy, invoke the Lambda to teardown the schema and user.
  # This must run BEFORE the Lambda infrastructure is destroyed.
  # If the function name can't be resolved (already destroyed), the script
  # exits 0 gracefully.
  before_hook "invoke_teardown" {
    commands     = ["destroy"]
    run_on_error = false
    execute = [
      "bash", "-c",
      <<-EOF
        # Check if there's any state to destroy
        RESOURCE_COUNT=$(terraform state list 2>/dev/null | wc -l || echo "0")
        if [[ "$RESOURCE_COUNT" -eq 0 ]]; then
          echo "[goose-migrator] No resources in state — nothing to teardown."
          exit 0
        fi

        FUNCTION_NAME=$(terraform output -raw function_name 2>/dev/null || echo "")
        if [[ -z "$FUNCTION_NAME" || "$FUNCTION_NAME" == "None" ]]; then
          echo "[goose-migrator] No function name in state — skipping teardown."
          exit 0
        fi

        "${local.scripts_dir}/invoke-goose-migrator.sh" \
          "$FUNCTION_NAME" \
          "teardown" \
          "${local.environment}"
      EOF
    ]
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPENDENCIES
# ---------------------------------------------------------------------------------------------------------------------

dependency "aurora-postgres" {
  config_path = "${get_terragrunt_dir()}/../../../core/aurora-postgres"

  mock_outputs = {
    cluster_master_username = "mock-user"
    cluster_endpoint        = "mock-cluster.cluster-abc123.eu-west-2.rds.amazonaws.com"
    cluster_port            = 5432
    cluster_database_name   = "mock_db"
    cluster_id              = "mock-cluster-id"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

dependency "network" {
  config_path = "${get_terragrunt_dir()}/../../../core/network"

  mock_outputs = {
    private_subnet_ids           = ["subnet-mock1", "subnet-mock2", "subnet-mock3"]
    lambda_rds_security_group_id = "sg-mock-rds"
    lambda_security_group_id     = "sg-mock-lambda"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

dependency "shared_services" {
  config_path = "${get_terragrunt_dir()}/../../../core/shared_services"

  mock_outputs = {
    kms_key_arn          = "arn:aws:kms:eu-west-2:123456789012:key/mock-key-id"
    pii_data_kms_key_arn = "arn:aws:kms:eu-west-2:123456789012:key/mock-pii-key-id"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "destroy"]
}

# ---------------------------------------------------------------------------------------------------------------------
# INPUTS - Passed to the Terraform module
# ---------------------------------------------------------------------------------------------------------------------

inputs = {
  environment = local.environment

  goose_migrator_zip_path = "${local.hometest_service_dir}/lambdas/goose-migrator/goose-migrator.zip"


  # Database connection info from Aurora cluster
  db_username   = dependency.aurora-postgres.outputs.cluster_master_username
  db_address    = dependency.aurora-postgres.outputs.cluster_endpoint
  db_port       = dependency.aurora-postgres.outputs.cluster_port
  db_name       = dependency.aurora-postgres.outputs.cluster_database_name
  db_cluster_id = dependency.aurora-postgres.outputs.cluster_id

  # Schema-per-environment configuration
  db_schema            = local.db_schema
  app_user_secret_name = local.app_user_secret_name

  # Authentication options
  use_iam_auth  = false
  grant_rds_iam = true

  # Network configuration for Lambda VPC access
  subnet_ids = dependency.network.outputs.private_subnet_ids
  security_group_ids = [
    dependency.network.outputs.lambda_rds_security_group_id,
    dependency.network.outputs.lambda_security_group_id
  ]

  # Encryption
  kms_key_arn = dependency.shared_services.outputs.pii_data_kms_key_arn
}
