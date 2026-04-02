################################################################################
# Data Sources
################################################################################

data "aws_availability_zones" "available" {
  state = "available"
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

data "aws_caller_identity" "current" {}

################################################################################
# Locals
################################################################################

locals {
  resource_prefix = "${var.project_name}-${var.aws_account_shortname}-${var.environment}"

  common_tags = merge(var.tags, {
    Component = "network"
  })

  # Calculate subnet CIDRs based on VPC CIDR
  # Using /20 for public (4096 IPs), /19 for private (8192 IPs), /21 for data (2048 IPs)
  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  # Data/database subnets always span >= 2 AZs (Aurora DB subnet group requirement)
  data_az_count = max(var.az_count, 2)
  data_azs      = slice(data.aws_availability_zones.available.names, 0, local.data_az_count)

  # Subnet CIDR calculations for a /16 VPC
  # Layout:
  #   Public  /20 (newbits=4):  indices 0-2   -> 10.0.0.0/20, 10.0.16.0/20, 10.0.32.0/20
  #   Private /19 (newbits=3):  indices 2-4   -> 10.0.64.0/19, 10.0.96.0/19, 10.0.128.0/19
  #   Firewall /22 (newbits=6): indices 48-50 -> 10.0.192.0/22, 10.0.196.0/22, 10.0.200.0/22
  #   Data    /21 (newbits=5):  indices 28-30 -> 10.0.224.0/21, 10.0.232.0/21, 10.0.240.0/21
  public_subnets = [
    for i, az in local.azs : cidrsubnet(var.vpc_cidr, 4, i)
  ]
  private_subnets = [
    for i, az in local.azs : cidrsubnet(var.vpc_cidr, 3, i + 2)
  ]
  data_subnets = [
    for i, az in local.data_azs : cidrsubnet(var.vpc_cidr, 5, i + 28)
  ]
  firewall_subnets = [
    for i, az in local.azs : cidrsubnet(var.vpc_cidr, 6, i + 48)
  ]
}
