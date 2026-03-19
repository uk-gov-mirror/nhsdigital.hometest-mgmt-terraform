# Domain overrides for uat environment.
# SPA and API use custom domains outside the POC wildcard cert scope,
# so dedicated per-env certificates are created by the hometest-app module.
locals {
  env_domain = "uat.hometest.service.nhs.uk"
  api_domain = "api.uat.hometest.service.nhs.uk"

  create_cloudfront_certificate = true
  create_api_certificate        = true
}
