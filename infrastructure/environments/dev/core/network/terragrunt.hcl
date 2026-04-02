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

# dev is non-production - az_count = 1 uses a single NAT GW and single firewall endpoint (~$65/month saving vs per-AZ)
# For production environments, remove this override to restore az_count = 3 (per-AZ NAT gateways + HA)
inputs = {
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
  allowed_egress_domains = [
    ".nhs.uk",                # NHS domains
    ".gov.uk",                # Government domains
    ".github.com",            # GitHub
    ".githubusercontent.com", # GitHub content
    # Add more domains as needed for your application
    ".prevx.io",          # Preventx staging/prod API
    ".preventx.com",      # Preventx website
    ".azurewebsites.net", # Preventx Azure functions
    ".sh24.org.uk"        # SH24 all environments
  ]
}
