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

  # ---------------------------------------------------------------------------
  # INGRESS FILTERING (inbound traffic to VPC)
  # ---------------------------------------------------------------------------
  # Ingress is IP + port based. Domain/URL filtering does NOT apply to inbound
  # traffic because the TLS SNI in an inbound connection contains YOUR domain,
  # not the client's. Use security groups and ALB/WAF for application-layer
  # ingress filtering.
  allowed_ingress_ips = [
    {
      ip          = "0.0.0.0/0"
      port        = "443"
      protocol    = "TCP"
      description = "HTTPS from anywhere (ALB/API Gateway)"
    },
    {
      ip          = "0.0.0.0/0"
      port        = "80"
      protocol    = "TCP"
      description = "HTTP from anywhere (redirect to HTTPS)"
    }
  ]

  # ---------------------------------------------------------------------------
  # EGRESS FILTERING (outbound traffic from VPC)
  # ---------------------------------------------------------------------------
  # Two mechanisms work together:
  #   1. Domain filter (allowed_egress_domains) — allowlists HTTPS/TLS traffic
  #      by inspecting TLS SNI and HTTP Host headers. Use for URLs/APIs.
  #   2. IP filter (allowed_egress_ips) — allowlists by IP/CIDR + port.
  #      Use for non-HTTPS protocols or endpoints without stable domains.
  #
  # IMPORTANT: Do NOT add 0.0.0.0/0 to allowed_egress_ips on port 443/80 —
  # it would bypass domain filtering and allow all HTTPS/HTTP traffic.
  # ---------------------------------------------------------------------------

  # IP-based egress: for specific non-HTTPS endpoints or IPs without domains
  allowed_egress_ips = [
    # Example: NTP time sync (UDP, can't use domain filter)
    # {
    #   ip          = "169.254.169.123/32"  # gitleaks:allow
    #   port        = "123"
    #   protocol    = "UDP"
    #   description = "Amazon Time Sync Service"
    # }
  ]

  # Domain-based egress: for HTTPS/TLS traffic (URLs and APIs)
  # AWS service domains (.amazonaws.com) are automatically allowed
  # Defined in _envcommon/all.hcl for consistency across environments
  allowed_egress_domains = local.global_vars.locals.allowed_egress_domains
}
