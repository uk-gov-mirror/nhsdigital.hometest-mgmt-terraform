# ---------------------------------------------------------------------------------------------------------------------
# TERRAGRUNT CONFIGURATION FOR staging ENVIRONMENT
# Deployment with: cd dev/hometest-app/staging/app && terragrunt apply
#
# All shared configuration (dependencies, lambda definitions, hooks) comes from _envcommon/hometest-app.hcl.
# Domain overrides and env flags are in ../env.hcl.
# Environment name ("staging") is derived from the parent directory name.
# Only truly env-specific overrides (e.g., extra lambdas) belong here.
# ---------------------------------------------------------------------------------------------------------------------

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "app" {
  path           = find_in_parent_folders("_envcommon/hometest-app.hcl")
  expose         = true
  merge_strategy = "deep"
}

# ---------------------------------------------------------------------------------------------------------------------
# ENVIRONMENT-SPECIFIC OVERRIDES
# Deep-merged with _envcommon/hometest-app.hcl inputs.
# Domain, certs, hooks, and lambda env vars are handled by app.hcl + env.hcl.
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
