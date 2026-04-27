# ---------------------------------------------------------------------------------------------------------------------
# TERRAGRUNT CONFIGURATION FOR dev-example ENVIRONMENT
# Deployment with: cd poc/hometest-app/dev-example/app && terragrunt apply
#
# All shared configuration (dependencies, lambda definitions, hooks) comes from _envcommon/hometest-app.hcl.
# Environment name ("dev-example") is derived from the parent directory name.
# ---------------------------------------------------------------------------------------------------------------------

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "app" {
  path           = find_in_parent_folders("_envcommon/hometest-app.hcl")
  expose         = true
  merge_strategy = "deep"
}

# Uses all defaults from ../app.hcl — no overrides needed.
# To add environment-specific overrides, uncomment and extend:
# inputs = {
#   lambdas = {
#     "my-custom-lambda" = { ... }
#   }
# }
