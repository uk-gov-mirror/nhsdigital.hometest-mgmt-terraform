# ---------------------------------------------------------------------------------------------------------------------
# TERRAGRUNT CONFIGURATION
# This is the configuration for Terragrunt, a thin wrapper for Terraform and OpenTofu that helps keep your code DRY and
# maintainable: https://github.com/gruntwork-io/terragrunt
# ---------------------------------------------------------------------------------------------------------------------

# Include the root `terragrunt.hcl` configuration. The root configuration contains settings that are common across all
# components and environments, such as how to configure remote state.
include "root" {
  path = find_in_parent_folders("root.hcl")
}

# ---------------------------------------------------------------------------------------------------------------------
# LOCALS - Load global configuration
# ---------------------------------------------------------------------------------------------------------------------

locals {
  global_vars = read_terragrunt_config(find_in_parent_folders("_envcommon/all.hcl"))
}

terraform {
  source = "../../../..//src/network"
}

dependency "bootstrap" {
  config_path = "../bootstrap"

  mock_outputs = {
    logs_kms_key_arn = "arn:aws:kms:eu-west-2:123456789012:key/mock-logs-key-id"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

# poc is non-production - cost optimisations vs production HA:
#   az_count = 1                     : single NAT GW + single firewall endpoint; ~$65/month saving vs per-AZ NAT,
#                                      ~$284/month saving vs 3 firewall endpoints (if network firewall enabled)
#                                      Note: data/database subnets always span >= 2 AZs (Aurora requirement)
#   enable_firewall_flow_logs = false : removes high-volume FLOW logs from CloudWatch (keep ALERT only)
#   firewall_logs_retention_days = 7  : reduces CloudWatch storage for POC logs
# For production, remove these overrides to restore az_count = 3 and full logging.
inputs = {
  logs_kms_key_arn             = dependency.bootstrap.outputs.logs_kms_key_arn
  enable_network_firewall      = true
  az_count                     = 1
  enable_firewall_flow_logs    = false
  firewall_logs_retention_days = 7

  # Allow specific domains for egress (HTTPS/TLS traffic)
  # Note: AWS service domains (.amazonaws.com) are automatically allowed
  # Defined in _envcommon/all.hcl for consistency across environments
  allowed_egress_domains = local.global_vars.locals.allowed_egress_domains
}
