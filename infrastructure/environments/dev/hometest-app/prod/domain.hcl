# Domain overrides for prod environment.
# SPA is served from the apex domain; API from the api. subdomain.
# Both require dedicated certs since *.poc.hometest.service.nhs.uk does not cover these.
locals {
  env_domain = "hometest.service.nhs.uk"
  api_domain = "api.hometest.service.nhs.uk"

  create_cloudfront_certificate = true
  create_api_certificate        = true
}
