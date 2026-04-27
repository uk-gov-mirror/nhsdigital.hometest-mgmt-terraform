# Slack Alerts Module

Integrates AWS Chatbot with Slack to route SNS alarm notifications to Slack channels.

## Features

- **Slack Integration**: AWS Chatbot channel configurations for Slack
- **Multi-Channel Support**: Route different alarm topics to different Slack channels
- **IAM Role**: Scoped Chatbot role with CloudWatch and Logs read access
- **Configurable Logging**: Adjustable Chatbot logging level

> **Prerequisite:** The Slack workspace must be authorized in the AWS Chatbot console before using this module (one-time manual step).

## Usage

```hcl
module "slack_alerts" {
  source = "../../modules/slack-alerts"

  project_name          = "nhs-hometest"
  aws_account_shortname = "prod"
  environment           = "prod"
  slack_workspace_id    = "T0123ABC456"

  slack_channels = {
    platform-alerts = {
      channel_id     = "C0123ABC456"
      sns_topic_arns = [module.alerts_topic.topic_arn]
    }
    security-alerts = {
      channel_id     = "C0789DEF012"
      sns_topic_arns = [module.security_topic.topic_arn]
    }
  }

  logging_level = "ERROR"

  tags = {
    Owner = "platform-team"
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| project_name | Name of the project | `string` | n/a | yes |
| aws_account_shortname | AWS account short name | `string` | n/a | yes |
| environment | Environment name | `string` | n/a | yes |
| slack_workspace_id | Slack workspace (team) ID from AWS Chatbot console | `string` | n/a | yes |
| slack_channels | Map of logical names to channel configs (`channel_id` and `sns_topic_arns`) | `map(object)` | `{}` | no |
| logging_level | Chatbot logging level: ERROR, INFO, or NONE | `string` | `"ERROR"` | no |
| tags | Additional tags | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| chatbot_role_arn | ARN of the IAM role used by Chatbot |
| channel_configurations | Map of Slack channel logical name to Chatbot configuration ARN |

## Best Practices

1. Separate alert channels by severity — critical alerts to an on-call channel, informational to a general channel.
2. Use the `logging_level` of `ERROR` in production to reduce Chatbot noise.
3. Combine with the alarm modules (`api-gateway-alarms`, `aurora-alarms`, etc.) and `sns` module for end-to-end alerting.
4. Store the `slack_workspace_id` and `channel_id` values in Terraform variables or SSM parameters rather than hardcoding.
