# CloudFront Alarms Module

CloudWatch alarms for monitoring AWS CloudFront distribution performance and error rates.

## Features

- **Error Rate Monitoring**: 5XX and 4XX error rate percentage alarms
- **Origin Latency**: Optional p99 origin latency alarm
- **Global Metrics**: Automatically targets `us-east-1` where CloudFront publishes metrics

> **Note:** CloudFront metrics are published to `us-east-1` regardless of where the distribution serves traffic. This module uses a provider alias accordingly.

## Usage

```hcl
module "cloudfront_alarms" {
  source = "../../modules/cloudfront-alarms"

  project_name          = "nhs-hometest"
  aws_account_shortname = "prod"
  environment           = "prod"
  distribution_id       = module.cloudfront.distribution_id

  alarm_actions     = [module.alerts_topic.topic_arn]
  enable_ok_actions = true

  alarm_5xx_threshold = 1
  alarm_4xx_threshold = 10

  # Enable if origin latency monitoring is needed
  create_origin_latency_alarm       = true
  alarm_origin_latency_threshold_ms = 5000

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
| distribution_id | CloudFront distribution ID to monitor | `string` | n/a | yes |
| alarm_actions | SNS topic ARNs for notifications | `list(string)` | `[]` | no |
| enable_ok_actions | Send notifications on OK state | `bool` | `false` | no |
| alarm_period | Evaluation period in seconds | `number` | `300` | no |
| alarm_evaluation_periods | Consecutive periods before triggering | `number` | `1` | no |
| alarm_5xx_threshold | 5XX error rate percentage threshold | `number` | `1` | no |
| alarm_4xx_threshold | 4XX error rate percentage threshold | `number` | `10` | no |
| create_origin_latency_alarm | Create origin latency alarm | `bool` | `false` | no |
| alarm_origin_latency_threshold_ms | Origin latency p99 threshold in milliseconds | `number` | `5000` | no |
| tags | Additional tags | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| alarm_5xx_arn | ARN of 5XX error rate alarm |
| alarm_4xx_arn | ARN of 4XX error rate alarm |
| alarm_origin_latency_arn | ARN of origin latency alarm (null if not created) |

## Best Practices

1. Keep 5XX threshold low (1%) — server errors from CloudFront indicate origin issues.
2. Set 4XX threshold higher to account for expected client errors (e.g., 404s for missing assets).
3. Enable origin latency alarms in production to detect backend degradation behind the CDN.
4. Ensure the calling module passes a `us-east-1` provider alias if deploying from another region.
