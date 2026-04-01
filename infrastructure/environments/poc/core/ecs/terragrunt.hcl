# ---------------------------------------------------------------------------------------------------------------------
# TERRAGRUNT CONFIGURATION FOR ECS CLUSTER
# Deploys the shared ECS Fargate cluster used by all environments.
# Must be deployed after network and shared_services.
# ---------------------------------------------------------------------------------------------------------------------

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/infrastructure//src/ecs-cluster"
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPENDENCIES
# ---------------------------------------------------------------------------------------------------------------------

dependency "network" {
  config_path = "../network"

  mock_outputs = {
    vpc_id            = "vpc-00000000000000000"
    public_subnet_ids = ["subnet-pub-mock1", "subnet-pub-mock2", "subnet-pub-mock3"]
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

dependency "shared_services" {
  config_path = "../shared_services"

  mock_outputs = {
    kms_key_arn                  = "arn:aws:kms:eu-west-2:000000000000:key/00000000-0000-0000-0000-000000000000"
    waf_regional_arn             = "arn:aws:wafv2:eu-west-2:000000000000:regional/webacl/mock/mock-id"
    acm_regional_certificate_arn = "arn:aws:acm:eu-west-2:000000000000:certificate/mock-cert"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

inputs = {
  vpc_id      = dependency.network.outputs.vpc_id
  kms_key_arn = dependency.shared_services.outputs.kms_key_arn

  log_retention_days = 30

  # Shared ALB
  enable_alb                   = true
  public_subnet_ids            = dependency.network.outputs.public_subnet_ids
  acm_regional_certificate_arn = dependency.shared_services.outputs.acm_regional_certificate_arn
  waf_regional_arn             = dependency.shared_services.outputs.waf_regional_arn
}
