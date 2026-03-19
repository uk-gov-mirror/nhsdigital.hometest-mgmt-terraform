# ---------------------------------------------------------------------------------------------------------------------
# TERRAGRUNT CONFIGURATION FOR prod ENVIRONMENT
# Deployment with: cd poc/hometest-app/prod && terragrunt apply
#
# All shared configuration (dependencies, lambda definitions, hooks) comes from ../app.hcl.
# Domain overrides (apex domain, api.hometest.* pattern) are in ./domain.hcl.
# Environment name ("prod") is derived automatically from this directory name.
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
