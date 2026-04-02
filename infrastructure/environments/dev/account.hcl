# Set account-wide variables. These are automatically pulled in to configure the remote state bucket in the root
# terragrunt.hcl configuration.
locals {
  # 781863586270 aws.hometest.poc@nhsdigital.nhs.uk
  aws_account_id        = "781195019563"
  aws_account_fullname  = "NHS HomeTest DEV"
  aws_account_name      = "nhs-hometest-dev"
  aws_account_shortname = "dev"

  github_allow_all_branches = true
}
