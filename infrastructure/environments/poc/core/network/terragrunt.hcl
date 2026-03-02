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

# poc is non-production - use single NAT gateway to reduce costs (~$65/month saving vs one per AZ)
# For production environments, remove this override to restore per-AZ NAT gateways (HA)
inputs = {
  single_nat_gateway = true
}
