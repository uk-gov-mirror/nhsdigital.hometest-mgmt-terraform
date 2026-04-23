# Set common variables for the environment. This is automatically pulled in in the root terragrunt.hcl configuration to
# feed forward to the child modules.
locals {
  environment = "lewis"

  enable_wiremock            = true
  wiremock_bypass_waf        = false
  wiremock_scheduled_scaling = false
}
