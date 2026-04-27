# ---------------------------------------------------------------------------------------------------------------------
# TERRAGRUNT CONFIGURATION
# Terragrunt is a thin wrapper for Terraform/OpenTofu that provides extra tools for working with multiple modules,
# remote state, and locking: https://github.com/gruntwork-io/terragrunt
# ---------------------------------------------------------------------------------------------------------------------

locals {
  # Automatically load account-level variables
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))

  # Automatically load region-level variables
  # region_vars = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  # Automatically load environment-level variables (optional - environments can define inline)
  # Uses find_in_parent_folders with fallback to a non-existent path; try() catches the read error
  _env_hcl_path = find_in_parent_folders("env.hcl", "${get_terragrunt_dir()}/__no_env_hcl__")
  _env_locals   = try(read_terragrunt_config(local._env_hcl_path).locals, {})

  # Automatically load global variables
  global_vars = read_terragrunt_config(find_in_parent_folders("_envcommon/all.hcl"))

  # Extract the variables we need for easy access
  region       = local.global_vars.locals.aws_region
  account_name = local.account_vars.locals.aws_account_name
  account_id   = local.account_vars.locals.aws_account_id

  # Environment: from env.hcl if available, otherwise derived from directory name
  environment = try(local._env_locals.environment, basename(path_relative_to_include()))

  # Verify that the AWS CLI is authenticated to the expected account
  # Set SKIP_AWS_ACCOUNT_CHECK=true to bypass this check (e.g. in pre-commit hooks)
  skip_account_check = get_env("SKIP_AWS_ACCOUNT_CHECK", "false") == "true"
  current_account_id = local.skip_account_check ? local.account_id : trimspace(run_cmd("--terragrunt-quiet", "aws", "sts", "get-caller-identity", "--query", "Account", "--output", "text"))
  account_check = (
    local.skip_account_check || local.current_account_id == local.account_id
    ? local.current_account_id
    : error("AWS account mismatch! Expected ${local.account_id} (${local.account_name}) but AWS CLI is authenticated to ${local.current_account_id}. Check your AWS profile/credentials.")
  )
}

# ---------------------------------------------------------------------------------------------------------------------
# TERRAFORM CONFIGURATION
# Settings applied to all terraform/tofu invocations across every module.
# ---------------------------------------------------------------------------------------------------------------------

# terragrunt --log-level debug plan
# find . -name ".terragrunt-cache" -type d | head -10 && echo "---" && du -sh poc/core/*/.terragrunt-cache 2>/dev/null && du -sh poc/hometest-app/dev/.terragrunt-cache 2>/dev/null
# terraform {
#   # Share a single provider plugin cache across all modules and dependency inits.
#   # Avoids re-downloading the AWS provider (~100MB) for each dependency resolution.
#   # Must include "init" and "output" — these are used by Terragrunt during dependency resolution.
#   extra_arguments "plugin_cache" {
#     commands = concat(
#       get_terraform_commands_that_need_vars(),
#       ["init", "output"]
#     )
#     env_vars = {
#       TF_PLUGIN_CACHE_DIR                            = "${get_repo_root()}/.terraform-plugin-cache"
#       TF_PLUGIN_CACHE_MAY_BREAK_DEPENDENCY_LOCK_FILE = "true"
#     }
#   }
# }

terraform {
  extra_arguments "parallelism" {
    commands  = ["plan", "apply", "destroy"]
    arguments = ["-parallelism=30"]
  }
}

remote_state {
  backend = "s3"
  config = {
    bucket       = "${local.account_name}-core-s3-tfstate"
    use_lockfile = true
    # IMPORTANT: This key derives `environment` from env.hcl (via find_in_parent_folders)
    # and uses basename(path) as the module name. For NESTED modules (e.g., dev/lambda-goose-migrator)
    # the basename alone is NOT unique across environments. Each env directory (dev/, uat/, etc.)
    # MUST have an env.hcl that sets `environment = "<name>"` to disambiguate the key.
    # Without it, all environments share the same key and overwrite each other's state.
    key        = "${local.account_name}-${local.environment}-${basename(path_relative_to_include())}.tfstate"
    encrypt    = true
    kms_key_id = "arn:aws:kms:${local.region}:${local.account_id}:alias/${local.account_name}-core-kms-tfstate-key"
    region     = local.region
  }
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# GLOBAL PARAMETERS
# These variables apply to all configurations in this subfolder. These are automatically merged into the child
# `terragrunt.hcl` config via the include block.
# ---------------------------------------------------------------------------------------------------------------------

# Configure root level variables that all resources can inherit. This is especially helpful with multi-account configs
# where terraform_remote_state data sources are placed directly into the modules.
inputs = merge(
  local.global_vars.locals,
  local.account_vars.locals,
  local._env_locals,
  {
    tags = {
      Owner       = "platform-team"
      CostCenter  = "infrastructure"
      Project     = local.global_vars.locals.project_name
      Environment = local.environment
      ManagedBy   = "terraform"
      Repository  = local.global_vars.locals.github_repo
    }
  }
)
