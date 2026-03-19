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
  path           = find_in_parent_folders("app.hcl")
  expose         = true
  merge_strategy = "deep"
}

# ---------------------------------------------------------------------------------------------------------------------
# ENVIRONMENT-SPECIFIC OVERRIDES
# Deep-merged with ../app.hcl inputs.
# Domain, certs, hooks, and lambda env vars are handled by app.hcl + domain.hcl.
# ---------------------------------------------------------------------------------------------------------------------

inputs = {
  # Hello World Lambda - simple health check (dev environment only)
  lambdas = {
    "hello-world-lambda" = {
      description     = "Hello World Lambda - Health Check"
      api_path_prefix = "hello-world"
      handler         = "index.handler"
      timeout         = 30
      memory_size     = 256
      environment = {
        NODE_OPTIONS = "--enable-source-maps"
        ENVIRONMENT  = basename(get_terragrunt_dir())
      }
    }
  }
}
