################################################################################
# Slack Alerts Module
# Configures AWS Chatbot integration to forward SNS alerts to Slack channels
################################################################################

locals {
  resource_prefix = "${var.project_name}-${var.aws_account_shortname}-${var.environment}"

  common_tags = merge(
    var.tags,
    {
      Name         = "${local.resource_prefix}-slack-alerts"
      Service      = "chatbot"
      ManagedBy    = "terraform"
      Module       = "slack-alerts"
      ResourceType = "chatbot-slack"
    }
  )
}

################################################################################
# IAM Role for AWS Chatbot
################################################################################

data "aws_iam_policy_document" "chatbot_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["chatbot.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "chatbot" {
  name               = "${local.resource_prefix}-chatbot-role"
  assume_role_policy = data.aws_iam_policy_document.chatbot_assume_role.json
  tags               = local.common_tags
}

data "aws_iam_policy_document" "chatbot_policy" {
  # Allow Chatbot to read CloudWatch metrics/alarms for context in messages
  statement {
    effect = "Allow"
    actions = [
      "cloudwatch:Describe*",
      "cloudwatch:Get*",
      "cloudwatch:List*",
    ]
    resources = ["*"]
  }

  # Allow Chatbot to describe logs for alarm context
  statement {
    effect = "Allow"
    actions = [
      "logs:Describe*",
      "logs:Get*",
      "logs:FilterLogEvents",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "chatbot" {
  name   = "${local.resource_prefix}-chatbot-policy"
  role   = aws_iam_role.chatbot.id
  policy = data.aws_iam_policy_document.chatbot_policy.json
}

################################################################################
# AWS Chatbot Slack Channel Configuration
# NOTE: The Slack workspace must first be authorized in the AWS Chatbot console.
# This is a one-time manual step per AWS account + Slack workspace.
################################################################################

resource "aws_chatbot_slack_channel_configuration" "channels" {
  for_each = var.slack_channels

  configuration_name = "${local.resource_prefix}-${each.key}"
  iam_role_arn       = aws_iam_role.chatbot.arn
  slack_channel_id   = each.value.channel_id
  slack_team_id      = var.slack_workspace_id

  sns_topic_arns = each.value.sns_topic_arns

  guardrail_policy_arns = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
  logging_level         = var.logging_level

  tags = merge(local.common_tags, {
    SlackChannel = each.key
  })
}
