# Set common variables for the environment. This is automatically pulled in in the root terragrunt.hcl configuration to
# feed forward to the child modules.
locals {
  environment = "staging"

  # Alerts disabled — only demo has alerts enabled
  enable_alerts = false

  # Domain overrides for staging environment.
  env_domain = "staging.hometest.service.nhs.uk"
  api_domain = "api.staging.hometest.service.nhs.uk"

  create_cloudfront_certificate = true
  create_api_certificate        = true
}
