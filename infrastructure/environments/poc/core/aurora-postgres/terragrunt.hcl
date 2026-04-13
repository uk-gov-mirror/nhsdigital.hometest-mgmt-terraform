# ---------------------------------------------------------------------------------------------------------------------
# TERRAGRUNT CONFIGURATION
# This deploys a PostgreSQL Aurora instance for POC environment
# ---------------------------------------------------------------------------------------------------------------------

# Include the root `terragrunt.hcl` configuration
include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  account_vars          = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  aws_account_shortname = local.account_vars.locals.aws_account_shortname
}

# Configure the version of the module to use in this environment
terraform {
  source = "../../../..//src/aurora-postgres"
}

# ---------------------------------------------------------------------------------------------------------------------
# Dependencies - Aurora requires network module to be deployed first
# ---------------------------------------------------------------------------------------------------------------------
dependency "network" {
  config_path = "../network"

  # Mock outputs for plan operations when network hasn't been deployed yet
  mock_outputs = {
    vpc_id                       = "vpc-mock-12345678"
    data_subnet_ids              = ["subnet-mock-1", "subnet-mock-2"]
    db_subnet_group_name         = "mock-db-subnet-group"
    lambda_security_group_id     = "sg-mock-lambda"
    lambda_rds_security_group_id = "sg-mock-lambda-rds"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

dependency "shared_services" {
  config_path = "../shared_services"

  mock_outputs = {
    kms_key_arn          = "arn:aws:kms:eu-west-2:123456789012:key/mock-key-id"
    pii_data_kms_key_arn = "arn:aws:kms:eu-west-2:123456789012:key/mock-pii-key-id"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

# ---------------------------------------------------------------------------------------------------------------------
# POC Environment Configuration
# PostgreSQL 18.1 on db.t4g.micro (cheapest ARM-based instance)
# Uses VPC and DB subnet group from the network module
# ---------------------------------------------------------------------------------------------------------------------
inputs = {
  # Network configuration from dependency
  vpc_id               = dependency.network.outputs.vpc_id
  db_subnet_group_name = dependency.network.outputs.db_subnet_group_name

  # Encryption - use shared_services PII data CMK for storage and master password secret
  kms_key_id                    = dependency.shared_services.outputs.pii_data_kms_key_arn
  master_user_secret_kms_key_id = dependency.shared_services.outputs.pii_data_kms_key_arn


  # Aurora Serverless v2 configuration
  db_name                   = "hometest_${local.aws_account_shortname}"
  username                  = "postgres"
  serverlessv2_min_capacity = 0.5
  serverlessv2_max_capacity = 4

  number_of_instances = 1

  # Network - Allow access from Lambda security groups only (least privilege)
  allowed_security_group_ids = [
    dependency.network.outputs.lambda_security_group_id,
    dependency.network.outputs.lambda_rds_security_group_id
  ]

  # Backup - minimal for POC (default is 7 days)
  backup_retention_period = 3
  skip_final_snapshot     = true  # Allow destruction without final snapshot
  deletion_protection     = false # Allow deletion for POC

  # Apply changes immediately in POC (default is false)
  apply_immediately = true

  # Enable IAM database authentication so Lambda functions can connect without passwords
  enable_iam_auth = true

  # Enable Data API for querying from AWS Console
  enable_http_endpoint = true
}
