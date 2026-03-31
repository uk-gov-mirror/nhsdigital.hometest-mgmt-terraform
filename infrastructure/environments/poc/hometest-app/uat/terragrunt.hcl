# ---------------------------------------------------------------------------------------------------------------------
# TERRAGRUNT CONFIGURATION FOR uat ENVIRONMENT
# Deployment with: cd poc/hometest-app/uat && terragrunt apply
#
# All shared configuration (dependencies, lambda definitions, hooks) comes from ../app.hcl.
# Domain overrides (custom cert, api.uat.* pattern) are in ./domain.hcl.
# Environment name ("uat") is derived automatically from this directory name.
# ---------------------------------------------------------------------------------------------------------------------

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "app" {
  path           = find_in_parent_folders("app.hcl")
  expose         = true
  merge_strategy = "deep"
}

# No environment-specific overrides needed.
# All inputs, hooks, and lambdas come from app.hcl.
# Domain and certificate config comes from domain.hcl.

inputs = {
  # WireMock - enabled for dev to stub 3rd-party APIs and support Playwright tests
  enable_wiremock = true
}
