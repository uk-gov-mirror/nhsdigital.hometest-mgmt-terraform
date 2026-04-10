# ---------------------------------------------------------------------------------------------------------------------
# TERRAGRUNT CONFIGURATION FOR prod ENVIRONMENT
# Deployment with: cd poc/hometest-app/prod/app && terragrunt apply
#
# All shared configuration (dependencies, lambda definitions, hooks) comes from _envcommon/hometest-app.hcl.
# Domain overrides (apex domain, api.hometest.* pattern) are in ../env.hcl.
# Environment name ("prod") is derived from the parent directory name.
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
