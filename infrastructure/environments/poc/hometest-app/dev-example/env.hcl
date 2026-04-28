# Set common variables for the environment. This is automatically pulled in in the root terragrunt.hcl configuration to
# feed forward to the child modules.
locals {
  # Environment name is auto-derived from the directory name.
  # Add optional overrides here (domain, WireMock, alerts, etc.)
}
