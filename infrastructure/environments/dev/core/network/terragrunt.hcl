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

# dev is non-production - az_count = 1 uses a single NAT GW and single firewall endpoint (~$65/month saving vs per-AZ)
# For production environments, remove this override to restore az_count = 3 (per-AZ NAT gateways + HA)
inputs = {
  logs_kms_key_arn = dependency.bootstrap.outputs.logs_kms_key_arn

  # Network Firewall - Enable for egress/ingress filtering
  enable_network_firewall      = true
  az_count                     = 1
  enable_firewall_flow_logs    = false
  firewall_logs_retention_days = 7

  firewall_default_deny = true

  # Allow specific inbound connections (e.g., from ALB, API Gateway)
  allowed_ingress_ips = [
    {
      ip          = "0.0.0.0/0"
      port        = "443"
      protocol    = "TCP"
      description = "HTTPS from anywhere"
    },
    {
      ip          = "0.0.0.0/0"
      port        = "80"
      protocol    = "TCP"
      description = "HTTP from anywhere"
    }
  ]

  # Allow specific outbound connections
  allowed_egress_ips = [
    {
      ip          = "0.0.0.0/0"
      port        = "443"
      protocol    = "TCP"
      description = "HTTPS from anywhere"
    },
    {
      ip          = "0.0.0.0/0"
      port        = "80"
      protocol    = "TCP"
      description = "HTTP from anywhere"
    }
    # Add specific external API endpoints here if needed
    # Example:
    # {
    #   ip          = "203.0.113.10/32"
    #   port        = "443"
    #   protocol    = "TCP"
    #   description = "External API"
    # }
  ]

  # Allow specific domains for egress (HTTPS/TLS traffic)
  # Note: AWS service domains (.amazonaws.com) are automatically allowed
  # Defined in _envcommon/all.hcl for consistency across environments
  allowed_egress_domains = local.global_vars.locals.allowed_egress_domains
}
