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

terraform {
  source = "../../../..//src/network"
}

# poc is non-production - cost optimisations vs production HA:
#   az_count = 1                     : single NAT GW + single firewall endpoint; ~$65/month saving vs per-AZ NAT,
#                                      ~$284/month saving vs 3 firewall endpoints (if network firewall enabled)
#                                      Note: data/database subnets always span >= 2 AZs (Aurora requirement)
#   enable_firewall_flow_logs = false : removes high-volume FLOW logs from CloudWatch (keep ALERT only)
#   firewall_logs_retention_days = 7  : reduces CloudWatch storage for POC logs
# For production, remove these overrides to restore az_count = 3 and full logging.
inputs = {
  az_count                     = 1
  enable_firewall_flow_logs    = false
  firewall_logs_retention_days = 7
}
