# ---------------------------------------------------------------------------------------------------------------------
# ACCOUNT-LEVEL CONFIGURATION FOR HOMETEST-APP (POC ACCOUNT)
# Location: poc/hometest-app/app.hcl
#
# Overrides that apply to ALL environments within the POC account.
# Loaded by _envcommon/hometest-app.hcl via find_in_parent_folders("app.hcl").
# Individual environments can further override these values in their env.hcl.
# ---------------------------------------------------------------------------------------------------------------------

locals {
  # ---------------------------------------------------------------------------
  # SECRET NAMES
  # POC account shares a single set of secrets across all environments.
  # ---------------------------------------------------------------------------
  secret_prefix                     = "nhs-hometest/dev"
  preventx_client_secret_name       = "${local.secret_prefix}/preventex-dev-client-secret"
  sh24_client_secret_name           = "${local.secret_prefix}/sh24-dev-client-secret"
  nhs_login_private_key_secret_name = "${local.secret_prefix}/nhs-login-private-key"
  os_places_creds_secret_name       = "${local.secret_prefix}/os-places-creds"

  # NHS Login Configuration (sandpit for POC)
  nhs_login_base_url  = "https://auth.sandpit.signin.nhs.uk"
  nhs_login_client_id = "hometest"
  nhs_login_scope     = "openid profile email phone"
}
