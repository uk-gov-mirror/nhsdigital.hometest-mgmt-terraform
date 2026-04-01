################################################################################
# AWS Region Management
# Disable opt-in regions and deny access to default regions via IAM policy
# Note: Default regions CANNOT be disabled via AWS API, only opt-in regions can
################################################################################

locals {
  # All AWS opt-in regions that can be enabled/disabled via aws_account_region
  opt_in_regions = [
    "af-south-1",     # Africa (Cape Town)
    "ap-east-1",      # Asia Pacific (Hong Kong)
    "ap-south-2",     # Asia Pacific (Hyderabad)
    "ap-southeast-3", # Asia Pacific (Jakarta)
    "ap-southeast-4", # Asia Pacific (Melbourne)
    "ap-southeast-5", # Asia Pacific (Malaysia)
    "ca-west-1",      # Canada (Calgary)
    "eu-central-2",   # Europe (Zurich)
    "eu-south-1",     # Europe (Milan)
    "eu-south-2",     # Europe (Spain)
    "il-central-1",   # Israel (Tel Aviv)
    "me-central-1",   # Middle East (UAE)
    "me-south-1",     # Middle East (Bahrain)
  ]

  # All AWS default regions (cannot be disabled, but can be denied via IAM/SCP)
  # Uncomment regions you want to DENY access to (regions NOT in allowed_regions)
  # Leave commented/remove regions you want to allow
  default_regions = [
    # US Regions
    # "us-east-1",      # US East (N. Virginia) - DO NOT ADD: Required for global services
    "us-east-2", # US East (Ohio)
    "us-west-1", # US West (N. California)
    "us-west-2", # US West (Oregon)

    # Asia Pacific Regions
    "ap-south-1",     # Asia Pacific (Mumbai)
    "ap-northeast-1", # Asia Pacific (Tokyo)
    "ap-northeast-2", # Asia Pacific (Seoul)
    "ap-northeast-3", # Asia Pacific (Osaka)
    "ap-southeast-1", # Asia Pacific (Singapore)
    "ap-southeast-2", # Asia Pacific (Sydney)

    # Canada
    "ca-central-1", # Canada (Central)

    # Europe Regions
    "eu-central-1", # Europe (Frankfurt)
    # "eu-west-1",      # Europe (Ireland) - DO NOT ADD: Secondary region
    # "eu-west-2",      # Europe (London) - DO NOT ADD: Primary region
    "eu-west-3",  # Europe (Paris)
    "eu-north-1", # Europe (Stockholm)

    # South America
    "sa-east-1", # South America (São Paulo)
  ]

  # Combine all regions and filter out allowed ones for IAM deny policy
  all_regions = concat(local.opt_in_regions, local.default_regions)

  regions_to_deny = [
    for region in local.all_regions : region
    if !contains(var.aws_allowed_regions, region)
  ]

  # Opt-in regions to disable (all of them since none are in allowed_regions)
  opt_in_regions_to_disable = [
    for region in local.opt_in_regions : region
    if !contains(var.aws_allowed_regions, region)
  ]

  regions_block_iam_role_name = "${local.resource_prefix}-iam-role-deny-non-allowed-regions"
}

################################################################################
# Disable Opt-In Regions (API-level disable)
################################################################################

resource "aws_account_region" "disabled" {
  for_each = toset(local.opt_in_regions_to_disable)

  region_name = each.value
  enabled     = false
}

################################################################################
# IAM Policy to Deny Access to Non-Allowed Regions
# Attach this to roles/users/groups to enforce region restrictions
################################################################################

resource "aws_iam_policy" "deny_regions" {
  name        = local.regions_block_iam_role_name
  description = "Denies access to all AWS regions except ${join(", ", var.aws_allowed_regions)}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "DenyNonAllowedRegions"
        Effect   = "Deny"
        Action   = "*"
        Resource = "*"
        Condition = {
          StringNotEquals = {
            "aws:RequestedRegion" = var.aws_allowed_regions
          }
          # Exclude global services that don't have a region
          "ForAnyValue:StringNotLike" = {
            "aws:PrincipalArn" = [
              "arn:aws:iam::*:root"
            ]
          }
        }
      },
      {
        Sid    = "AllowGlobalServices"
        Effect = "Allow"
        Action = [
          # IAM is global
          "iam:*",
          # Organizations is global
          "organizations:*",
          # STS is global (but also regional)
          "sts:GetCallerIdentity",
          # Route53 is global
          "route53:*",
          "route53domains:*",
          # CloudFront is global
          "cloudfront:*",
          # WAF Global
          "waf:*",
          "wafv2:*",
          # Shield is global
          "shield:*",
          # Global Accelerator
          "globalaccelerator:*",
          # Support is global
          "support:*",
          # Billing/Cost
          "aws-portal:*",
          "budgets:*",
          "ce:*",
          "cur:*",
          # Account management
          "account:*"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = local.regions_block_iam_role_name
  })
}

# Attach to GitHub Actions role to enforce region restrictions
resource "aws_iam_role_policy_attachment" "gha_deny_regions" {
  role       = aws_iam_role.gha_oidc_role.name
  policy_arn = aws_iam_policy.deny_regions.arn
}

################################################################################
# Outputs
################################################################################

output "disabled_opt_in_regions" {
  description = "List of opt-in AWS regions that have been disabled"
  value       = local.opt_in_regions_to_disable
}

output "denied_regions" {
  description = "List of all AWS regions denied via IAM policy"
  value       = local.regions_to_deny
}

output "allowed_regions" {
  description = "List of AWS regions that are allowed"
  value       = var.aws_allowed_regions
}

output "deny_regions_policy_arn" {
  description = "ARN of the IAM policy that denies non-allowed regions"
  value       = aws_iam_policy.deny_regions.arn
}
