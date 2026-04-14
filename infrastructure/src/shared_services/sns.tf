################################################################################
# SNS Topics
# Shared SNS topics for the hometest application
################################################################################

#------------------------------------------------------------------------------
# Alerts Topic (existing — general-purpose alerts)
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

#------------------------------------------------------------------------------
# Critical Alerts Topic
# P1 alerts: Lambda errors, DLQ messages, 5XX spikes, DB deadlocks
#------------------------------------------------------------------------------

module "sns_alerts_critical" {
  source = "../../modules/sns"

  project_name          = var.project_name
  aws_account_shortname = var.aws_account_shortname
  environment           = var.environment
  topic_name_suffix     = "alerts-critical"

  display_name      = "HomeTest Critical Alerts"
  kms_master_key_id = aws_kms_key.main.id

  subscriptions = local.sns_alerts_email_subscriptions

  tags = local.common_tags
}

#------------------------------------------------------------------------------
# Warning Alerts Topic
# P2 alerts: High latency, capacity warnings, WAF blocks
#------------------------------------------------------------------------------

module "sns_alerts_warning" {
  source = "../../modules/sns"

  project_name          = var.project_name
  aws_account_shortname = var.aws_account_shortname
  environment           = var.environment
  topic_name_suffix     = "alerts-warning"

  display_name      = "HomeTest Warning Alerts"
  kms_master_key_id = aws_kms_key.main.id

  subscriptions = local.sns_alerts_email_subscriptions

  tags = local.common_tags
}

#------------------------------------------------------------------------------
# Security Alerts Topic
# WAF SQL injection, rate limiting, unusual blocked request spikes
#------------------------------------------------------------------------------

module "sns_alerts_security" {
  source = "../../modules/sns"

  project_name          = var.project_name
  aws_account_shortname = var.aws_account_shortname
  environment           = var.environment
  topic_name_suffix     = "alerts-security"

  display_name      = "HomeTest Security Alerts"
  kms_master_key_id = aws_kms_key.main.id

  subscriptions = local.sns_alerts_email_subscriptions

  tags = local.common_tags
}

################################################################################
# Slack Integration (SNS → Lambda → Webhook)
# The Lambda reads the incoming webhook URL from Secrets Manager and posts
# formatted alarm messages to the configured Slack channel.
################################################################################

module "slack_alerts" {
  source = "../../modules/slack-alerts"
  count  = var.enable_slack_alerts ? 1 : 0

  project_name          = var.project_name
  aws_account_shortname = var.aws_account_shortname
  environment           = var.environment

  slack_webhook_secret_name = var.slack_webhook_secret_name
  slack_channel_name        = var.slack_channel_name

  # All tiered SNS topics route to the same channel — override per-channel later if needed
  sns_topic_arns = [
    module.sns_alerts_critical.topic_arn,
    module.sns_alerts_warning.topic_arn,
    module.sns_alerts_security.topic_arn,
  ]

  kms_key_arn = aws_kms_key.main.id

  tags = local.common_tags
}
