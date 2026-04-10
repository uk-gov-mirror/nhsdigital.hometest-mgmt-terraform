# ---------------------------------------------------------------------------------------------------------------------
# TERRAGRUNT CONFIGURATION FOR uat ENVIRONMENT
# Deployment with: cd poc/hometest-app/uat/app && terragrunt apply
#
# All shared configuration (dependencies, lambda definitions, hooks) comes from _envcommon/hometest-app.hcl.
# Domain overrides and env flags (WireMock etc.) are in ../env.hcl.
# Environment name ("uat") is derived from the parent directory name.
# ---------------------------------------------------------------------------------------------------------------------

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "app" {
  path           = find_in_parent_folders("_envcommon/hometest-app.hcl")
  expose         = true
  merge_strategy = "deep"
}

# No environment-specific overrides needed.
# All inputs, hooks, and lambdas come from app.hcl.
# Domain and certificate config comes from domain.hcl.

# locals {
#   enable_wiremock = true
# }

inputs = {
  # (enable_wiremock is controlled via env.hcl so that the same flag also
  #  steers the SPA build-time env vars in the before_hook.)
}
