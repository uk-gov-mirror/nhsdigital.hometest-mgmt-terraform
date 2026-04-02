# ---------------------------------------------------------------------------------------------------------------------
# TERRAGRUNT CONFIGURATION FOR UAT ENVIRONMENT GOOSE MIGRATOR
# Deployment: cd poc/hometest-app/uat/lambda-goose-migrator && terragrunt apply
#
# All shared configuration (dependencies, inputs) comes from ../goose-migrator.hcl.
# Environment name ("uat") is derived automatically from the parent directory name.
# ---------------------------------------------------------------------------------------------------------------------

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "goose-migrator" {
  path           = find_in_parent_folders("_envcommon/goose-migrator.hcl")
  expose         = true
  merge_strategy = "deep"
}

# No environment-specific overrides needed.
# All inputs and dependencies come from goose-migrator.hcl.
