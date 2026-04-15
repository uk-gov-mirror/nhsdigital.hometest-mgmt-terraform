################################################################################
# Slack Alerts Module Outputs
################################################################################

output "chatbot_role_arn" {
  description = "ARN of the IAM role used by AWS Chatbot"
  value       = aws_iam_role.chatbot.arn
}

output "channel_configurations" {
  description = "Map of Chatbot Slack channel configuration ARNs"
  value = {
    for k, v in aws_chatbot_slack_channel_configuration.channels : k => v.chat_configuration_arn
  }
}
