# Set common variables for the environment. This is automatically pulled in in the root terragrunt.hcl configuration to
# feed forward to the child modules.
locals {
  environment = "demo"

  # Alerts enabled for demo environment
  enable_alerts = true

  # Domain overrides for demo environment.
  env_domain = "demo.hometest.service.nhs.uk"
  api_domain = "api.demo.hometest.service.nhs.uk"

  create_cloudfront_certificate = true
  create_api_certificate        = true
}
