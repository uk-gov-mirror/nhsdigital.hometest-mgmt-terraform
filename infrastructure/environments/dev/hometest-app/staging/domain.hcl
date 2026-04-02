# Domain overrides for dev environment.
# SPA and API use custom domains outside the POC wildcard cert scope,
# so dedicated per-env certificates are created by the hometest-app module.
locals {
  env_domain = "staging.devtest.hometest.service.nhs.uk"
  api_domain = "api-staging.devtest.hometest.service.nhs.uk"

  create_cloudfront_certificate = false
  create_api_certificate        = false
}
