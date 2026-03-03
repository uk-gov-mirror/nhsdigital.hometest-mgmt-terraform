# ---------------------------------------------------------------------------------------------------------------------
# DB IAM AUTH TEST — UAT
#
# Deploys a lightweight Lambda that connects as app_user_hometest_uat using IAM auth
# and runs diagnostic queries. Use this to verify the full IAM auth chain works.
#
# Deploy:  cd poc/hometest-app/uat/lambda-db-auth-test && terragrunt apply
# Invoke:  aws lambda invoke --function-name nhs-hometest-poc-uat-lambda-db-auth-test --region eu-west-2 /dev/stdout
# Destroy: cd poc/hometest-app/uat/lambda-db-auth-test && terragrunt destroy
# ---------------------------------------------------------------------------------------------------------------------

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/infrastructure//src/lambda-db-auth-test"
}

dependency "aurora-postgres" {
  config_path = "${get_terragrunt_dir()}/../../../core/aurora-postgres"

  mock_outputs = {
    cluster_endpoint      = "mock-cluster.cluster-abc123.eu-west-2.rds.amazonaws.com"
    cluster_port          = 5432
    cluster_database_name = "mock_db"
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

locals {
  environment = basename(dirname(get_terragrunt_dir()))
  db_schema   = "hometest_${local.environment}"
}

inputs = {
  environment = local.environment

  db_address = dependency.aurora-postgres.outputs.cluster_endpoint
  db_port    = dependency.aurora-postgres.outputs.cluster_port
  db_name    = dependency.aurora-postgres.outputs.cluster_database_name
  db_schema  = local.db_schema

  app_user_secret_name = "nhs-hometest/${local.environment}/app-user-db-secret"

  subnet_ids = dependency.network.outputs.private_subnet_ids
  security_group_ids = [
    dependency.network.outputs.lambda_rds_security_group_id,
    dependency.network.outputs.lambda_security_group_id
  ]
}
