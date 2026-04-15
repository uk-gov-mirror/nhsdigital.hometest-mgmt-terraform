# Set common variables for the environment. This is automatically pulled in in the root terragrunt.hcl configuration to
# feed forward to the child modules.
locals {
  environment = "prod"

  # Alerts disabled — only demo has alerts enabled
  enable_alerts = false

  # Domain overrides for prod environment.
  # SPA is served from the apex domain; API from the api. subdomain.
  # Both require dedicated certs since *.poc.hometest.service.nhs.uk does not cover these.
  env_domain = "hometest.service.nhs.uk"
  api_domain = "api.hometest.service.nhs.uk"

  create_cloudfront_certificate = true
  create_api_certificate        = true
}
