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
# Slack Integration (AWS Chatbot)
# NOTE: The Slack workspace must first be authorized in the AWS Chatbot console.
# This is a one-time manual step per AWS account.
################################################################################

module "slack_alerts" {
  source = "../../modules/slack-alerts"
  count  = var.enable_slack_alerts ? 1 : 0

  project_name          = var.project_name
  aws_account_shortname = var.aws_account_shortname
  environment           = var.environment

  slack_workspace_id = var.slack_workspace_id

  slack_channels = {
    critical = {
      channel_id     = var.slack_channel_id_critical
      sns_topic_arns = [module.sns_alerts_critical.topic_arn]
    }
    warning = {
      channel_id     = var.slack_channel_id_warning
      sns_topic_arns = [module.sns_alerts_warning.topic_arn]
    }
    security = {
      channel_id     = var.slack_channel_id_security
      sns_topic_arns = [module.sns_alerts_security.topic_arn]
    }
  }

  tags = local.common_tags
}
