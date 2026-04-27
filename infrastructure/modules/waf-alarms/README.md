# WAF Alarms Module

CloudWatch alarms for monitoring AWS WAFv2 Web ACL threat activity.

## Features

- **Blocked Request Spikes**: Alarm when blocked requests exceed threshold
- **Rate Limiting**: Optional alarm when rate-limiting rules are triggered
- **SQL Injection Detection**: Optional alarm for SQL injection attack attempts
- **Regional Support**: Configurable region for WAF metrics

## Usage

```hcl
module "waf_alarms" {
  source = "../../modules/waf-alarms"

  project_name          = "nhs-hometest"
  aws_account_shortname = "prod"
  environment           = "prod"
  aws_region            = "eu-west-2"
  web_acl_name          = "prod-web-acl"
  waf_name_suffix       = "regional"

  alarm_actions     = [module.alerts_topic.topic_arn]
  enable_ok_actions = true

  alarm_blocked_threshold = 100

  # Enable rule-specific alarms with CloudWatch metric names from WAF rules
  rate_limit_metric_name = "RateLimitRule"
  sqli_metric_name       = "SQLInjectionRule"

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
| aws_region | AWS region where WAF is deployed | `string` | n/a | yes |
| web_acl_name | WAFv2 Web ACL name | `string` | n/a | yes |
| waf_name_suffix | Suffix for alarm naming (e.g., 'regional', 'cloudfront') | `string` | n/a | yes |
| alarm_actions | SNS topic ARNs for notifications | `list(string)` | `[]` | no |
| enable_ok_actions | Send notifications on OK state | `bool` | `false` | no |
| alarm_period | Evaluation period in seconds | `number` | `300` | no |
| alarm_evaluation_periods | Consecutive periods before triggering | `number` | `1` | no |
| alarm_blocked_threshold | Blocked requests spike threshold | `number` | `100` | no |
| rate_limit_metric_name | CloudWatch metric name for rate-limit WAF rule (null to skip) | `string` | `null` | no |
| sqli_metric_name | CloudWatch metric name for SQL injection WAF rule (null to skip) | `string` | `null` | no |
| tags | Additional tags | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| alarm_blocked_spike_arn | ARN of blocked requests spike alarm |
| alarm_rate_limited_arn | ARN of rate-limited alarm (null if not created) |
| alarm_sqli_detected_arn | ARN of SQL injection detection alarm (null if not created) |

## Best Practices

1. Set the blocked threshold based on normal traffic patterns — a sudden spike often indicates an attack.
2. Enable SQL injection alarms in production to detect active exploitation attempts.
3. Use `waf_name_suffix` to distinguish between regional and CloudFront-associated WAF alarms.
4. Rule-specific metric names must match the CloudWatch metric names configured in your WAF rules.
