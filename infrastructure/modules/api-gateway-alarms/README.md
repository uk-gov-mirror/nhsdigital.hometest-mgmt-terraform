# API Gateway Alarms Module

CloudWatch alarms for monitoring AWS API Gateway REST API health and performance.

## Features

- **Error Rate Monitoring**: 5XX and 4XX error rate percentage alarms using metric math
- **Latency Tracking**: p99 latency and integration latency alarms
- **Multi-API Support**: Monitor multiple API Gateway REST APIs from a single module instance
- **Naming Convention**: `<project>-<account_shortname>-<environment>-<api_name>-<metric>`

## Usage

```hcl
module "api_gateway_alarms" {
  source = "../../modules/api-gateway-alarms"

  project_name         = "nhs-hometest"
  aws_account_shortname = "prod"
  environment          = "prod"

  api_names = ["orders-api", "users-api"]

  alarm_actions    = [module.alerts_topic.topic_arn]
  enable_ok_actions = true

  alarm_5xx_threshold                  = 1
  alarm_4xx_threshold                  = 10
  alarm_latency_threshold_ms           = 3000
  alarm_integration_latency_threshold_ms = 2000

  tags = {
    Owner = "platform-team"
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| project_name | Name of the project | `string` | n/a | yes |
| aws_account_shortname | AWS account short name for naming convention | `string` | n/a | yes |
| environment | Environment name | `string` | n/a | yes |
| api_names | Set of API Gateway REST API names to monitor | `set(string)` | n/a | yes |
| alarm_actions | SNS topic ARNs to notify on alarm trigger | `list(string)` | `[]` | no |
| enable_ok_actions | Send notifications for OK state transitions | `bool` | `false` | no |
| alarm_period | Evaluation period in seconds | `number` | `300` | no |
| alarm_evaluation_periods | Consecutive periods before triggering | `number` | `1` | no |
| alarm_5xx_threshold | 5XX error rate percentage threshold | `number` | `1` | no |
| alarm_4xx_threshold | 4XX error rate percentage threshold | `number` | `10` | no |
| alarm_latency_threshold_ms | p99 latency threshold in milliseconds | `number` | `3000` | no |
| alarm_integration_latency_threshold_ms | p99 integration latency threshold in milliseconds | `number` | `2000` | no |
| tags | Additional tags | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| alarm_5xx_arns | Map of API name to 5XX error alarm ARN |
| alarm_4xx_arns | Map of API name to 4XX error alarm ARN |
| alarm_latency_arns | Map of API name to latency alarm ARN |
| alarm_integration_latency_arns | Map of API name to integration latency alarm ARN |

## Best Practices

1. Enable OK actions in production to track alarm recovery.
2. Tune 4XX thresholds per environment — higher in dev, stricter in prod.
3. Use integration latency alarms to detect backend bottlenecks separately from API Gateway overhead.
4. Combine with the `slack-alerts` module to route alarm notifications to Slack.
