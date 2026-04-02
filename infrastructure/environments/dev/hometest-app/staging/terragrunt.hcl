# ---------------------------------------------------------------------------------------------------------------------
# TERRAGRUNT CONFIGURATION FOR dev ENVIRONMENT
# Deployment with: cd poc/hometest-app/dev && terragrunt apply
#
# All shared configuration (dependencies, lambda definitions, hooks) comes from ../app.hcl.
# Domain overrides (custom cert, api.dev.* pattern) are in ./domain.hcl.
# Environment name ("dev") is derived automatically from this directory name.
# Only truly env-specific overrides (e.g., extra lambdas) belong here.
# ---------------------------------------------------------------------------------------------------------------------

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "app" {
  path           = find_in_parent_folders("_envcommon/app.hcl")
  expose         = true
  merge_strategy = "deep"
}

# ---------------------------------------------------------------------------------------------------------------------
# ENVIRONMENT-SPECIFIC OVERRIDES
# Deep-merged with ../app.hcl inputs.
# Domain, certs, hooks, and lambda env vars are handled by app.hcl + domain.hcl.
# ---------------------------------------------------------------------------------------------------------------------

inputs = {
  # TEMPORARY FIX: staging uses devtest.hometest.service.nhs.uk zone (Z10312861T421RGJG6CVB)
  # instead of the default hometest.service.nhs.uk zone from the network module.
  # TODO: Remove once the network module outputs the correct zone for this subenv.
  route53_zone_id = "Z10312861T421RGJG6CVB"
}
