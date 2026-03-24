################################################################################
# SNS Topics
# Shared SNS topics for the hometest application
################################################################################

#------------------------------------------------------------------------------
# Alerts Topic
# Used for infrastructure and SQS alarm notifications
#------------------------------------------------------------------------------

locals {
  sns_alerts_email_subscriptions = {
    for email in var.sns_alerts_email_subscriptions : "email_${substr(md5(email), 0, 8)}" => {
      protocol = "email"
      endpoint = email
    }
  }
}

module "sns_alerts" {
  source = "../../modules/sns"

  project_name          = var.project_name
  aws_account_shortname = var.aws_account_shortname
  environment           = var.environment
  topic_name_suffix     = "alerts"

  # Encryption
  kms_master_key_id = aws_kms_key.main.id

  # Subscriptions
  subscriptions = local.sns_alerts_email_subscriptions

  # Tags
  tags = local.common_tags
}
