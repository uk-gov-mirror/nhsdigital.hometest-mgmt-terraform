# Domain overrides for dev environment.
# SPA and API use custom domains outside the POC wildcard cert scope,
# so dedicated per-env certificates are created by the hometest-app module.
locals {
  env_domain = "dev.hometest.service.nhs.uk"
  api_domain = "api.dev.hometest.service.nhs.uk"

  create_cloudfront_certificate = true
  create_api_certificate        = true
}
