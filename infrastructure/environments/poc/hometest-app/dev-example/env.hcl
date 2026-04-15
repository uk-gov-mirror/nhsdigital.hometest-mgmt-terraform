# Set common variables for the environment. This is automatically pulled in in the root terragrunt.hcl configuration to
# feed forward to the child modules.
locals {
  environment = "dev-example"

  # Alerts disabled — only demo has alerts enabled
  enable_alerts = false
}
