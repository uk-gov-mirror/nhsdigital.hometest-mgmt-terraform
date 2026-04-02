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
    vpc_id               = "vpc-mock-12345678"
    data_subnet_ids      = ["subnet-mock-1", "subnet-mock-2"]
    db_subnet_group_name = "mock-db-subnet-group"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
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


  # Aurora Serverless v2 configuration
  db_name                   = "hometest_${local.aws_account_shortname}"
  username                  = "postgres"
  serverlessv2_min_capacity = 0.5
  serverlessv2_max_capacity = 4

  number_of_instances = 1

  # Network - Allow access from VPC CIDR for POC
  allowed_cidr_blocks = ["10.0.0.0/16"]

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
