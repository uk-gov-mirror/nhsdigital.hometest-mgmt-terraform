# HomeTest Monitoring & Alerting

This document describes the monitoring, alerting, and notification infrastructure for NHS HomeTest.

## Architecture Overview

```
CloudWatch Alarms → SNS Topics (tiered) → Lambda → Slack Webhook → #hometest-ops-alerts
                                        → Email subscriptions
GitHub Actions    → Slack Webhook (secret) → #hometest-ops-alerts
```

All CloudWatch alarms publish to one of three tiered SNS topics in `shared_services`. A Lambda function subscribes to each topic and forwards formatted messages to Slack via an incoming webhook stored in AWS Secrets Manager.

GitHub Actions deployment notifications use a separate webhook stored as a repository secret.

---

## SNS Topics (Alert Tiers)

| Topic Suffix | Severity | Purpose | Examples |
|---|---|---|---|
| `alerts-critical` | P1 | Service-impacting issues requiring immediate attention | Lambda errors, DLQ messages, 5XX spikes, DB deadlocks, SQS age threshold |
| `alerts-warning` | P2 | Capacity/performance degradation | High latency, NAT port allocation errors, Aurora capacity approaching limits |
| `alerts-security` | P3 | Security events | WAF blocked request spikes, SQL injection attempts, rate limiting triggers |

All topics also send to the email subscriptions configured in `sns_alerts_email_subscriptions` (currently `england.HomeTestInfraAdmins@nhs.net`).

---

## Slack Integration

### Infrastructure Alerts (SNS → Lambda → Webhook)

- **Module**: `infrastructure/modules/slack-alerts`
- **Deployed in**: `shared_services` layer
- **Mechanism**: A Node.js Lambda function reads the webhook URL from Secrets Manager and posts formatted alarm messages to Slack
- **Secrets Manager secret**: `nhs-hometest/slack/hometest-ops-alerts/incoming-webhook`
- **Slack channel**: `#hometest-ops-alerts`

The Lambda colour-codes messages by severity:

| Colour | Severity | Trigger |
|---|---|---|
| 🔴 Red | CRITICAL | Topic name contains `critical` |
| 🟠 Orange | SECURITY | Topic name contains `security` |
| 🟡 Yellow | WARNING | Topic name contains `warning` |
| 🟢 Green | INFO | Fallback |

#### Terragrunt Configuration

```hcl
# infrastructure/environments/<account>/core/shared_services/terragrunt.hcl
inputs = {
  enable_slack_alerts        = true
  slack_webhook_secret_name  = "nhs-hometest/slack/hometest-ops-alerts/incoming-webhook"
  slack_channel_name         = "hometest-ops-alerts"
}
```

To disable Slack alerts for an environment, set `enable_slack_alerts = false`. Email alerts continue independently.

#### Splitting Channels (Future)

The architecture supports routing different severity tiers to separate Slack channels by deploying multiple instances of the `slack-alerts` module with different `sns_topic_arns` and `slack_webhook_secret_name` / `slack_channel_name` values. Each channel would need its own incoming webhook stored in Secrets Manager.

### Deployment Notifications (GitHub Actions → Webhook)

- **Action**: `.github/actions/notify-slack`
- **Secret**: `SLACK_WEBHOOK_URL` (GitHub Actions repository secret)
- **Triggers**: End of `cicd-3-deploy` and `deploy-tf-hometest-app` workflows
- **Content**: Deployment status (success/failure/cancelled), environment, module, actor, and a link to the run

---

## CloudWatch Alarms by Layer

### shared_services

#### WAF Alarms (`modules/waf-alarms`)

| Alarm | Metric | Threshold | Severity |
|---|---|---|---|
| Blocked Request Spike | BlockedRequests | > 100 in 5 min | Security |
| Rate Limit Triggered | RateLimitRule count | > 0 in 5 min | Security |
| SQLi Detected | SQLiRule count | > 0 in 5 min | Security |

Applied to both the regional WAF (API Gateway/ALB) and CloudFront WAF.

#### Network Alarms (`modules/network-alarms`)

| Alarm | Metric | Threshold | Severity |
|---|---|---|---|
| NAT GW Port Allocation Errors | ErrorPortAllocation | > 0 in 5 min | Warning |
| NAT GW Packets Dropped | PacketsDropCount | > 100 in 5 min | Warning |
| Network Firewall Dropped Packets | DroppedPackets | > 100 in 5 min | Warning |

NAT Gateway alarms are created per gateway via `for_each`.

### aurora-postgres

#### Aurora Alarms (`modules/aurora-alarms`)

| Alarm | Metric | Threshold | Severity |
|---|---|---|---|
| High CPU | CPUUtilization | > 80% avg over 5 min | Critical |
| Low Freeable Memory | FreeableMemory | < 256 MB avg over 5 min | Critical |
| High Connections | DatabaseConnections | > 100 avg over 5 min | Critical |
| Deadlocks | Deadlocks | > 0 sum in 5 min | Critical |
| Replica Lag | AuroraReplicaLag | > 100 ms avg over 5 min | Critical |
| High Serverless Capacity | ServerlessDatabaseCapacity | > max ACU × 80% | Critical |
| Low Free Storage | FreeLocalStorage | < 5 GB avg over 5 min | Critical |

Thresholds are configurable via the module variables.

### hometest-app

#### Lambda Alarms (built into `modules/lambda`)

Each Lambda function gets these alarms automatically:

| Alarm | Metric | Threshold | Severity |
|---|---|---|---|
| Errors | Errors | ≥ 1 sum in 1 min | Critical |
| Throttles | Throttles | ≥ 1 sum in 1 min | Critical |
| Duration (p99) | Duration (p99) | ≥ timeout × 80% | Critical |
| Concurrent Executions | ConcurrentExecutions | ≥ reserved × 80% | Critical |

The concurrency alarm is only created when `reserved_concurrent_executions > 0`.

#### SQS Alarms (built into `modules/sqs`)

Each SQS queue gets an `ApproximateAgeOfOldestMessage` alarm. The following queues are monitored:

- `order-placement`
- `order-result`
- `order-notification`
- `order-eviction`
- `supplier-notification`

Each queue also has a dead-letter queue (DLQ) with its own age alarm.

#### API Gateway Alarms (`modules/api-gateway-alarms`)

| Alarm | Metric | Threshold | Severity |
|---|---|---|---|
| 5XX Error Rate | 5XXError / Count × 100 | > 1% in 5 min | Critical |
| 4XX Error Rate | 4XXError / Count × 100 | > 10% in 5 min | Critical |
| Latency (p99) | Latency (p99) | > 3000 ms in 5 min | Critical |
| Integration Latency (p99) | IntegrationLatency (p99) | > 2000 ms in 5 min | Critical |

#### CloudFront Alarms (`modules/cloudfront-alarms`)

| Alarm | Metric | Threshold | Severity |
|---|---|---|---|
| 5XX Error Rate | 5xxErrorRate | > 1% in 5 min | Critical |
| 4XX Error Rate | 4xxErrorRate | > 10% in 5 min | Critical |
| Origin Latency (p99) | OriginLatency (p99) | > 5000 ms in 5 min | Critical |

---

## Threshold Tuning

All alarm thresholds are configurable via module variables. Default values are chosen for a typical workload and should be reviewed per environment:

- **POC/Dev**: Defaults are usually fine; consider relaxing to avoid noise during development.
- **Production**: Review thresholds against actual traffic patterns. Tighten error rate thresholds and shorten evaluation periods.

To override a threshold, set the corresponding variable in the terragrunt inputs for the relevant layer.

---

## Adding New Alarms

1. **Determine the layer**: Which Terraform source deploys the resource? (`shared_services`, `hometest-app`, `aurora-postgres`)
2. **Choose the severity**: Critical (P1), Warning (P2), or Security (P3)
3. **Create or extend a module**: Add the CloudWatch alarm with `alarm_actions = [var.sns_alerts_<severity>_topic_arn]`
4. **Wire in the source**: Reference the module in the appropriate `src/*/alarms.tf` file
5. **Pass the SNS topic ARN**: Ensure the terragrunt config passes the topic ARN from `shared_services` outputs

---

## Troubleshooting

### Slack messages not arriving

1. Verify the Lambda is deployed: `aws lambda get-function --function-name <prefix>-slack-notifier`
2. Check Lambda logs: CloudWatch log group `/aws/lambda/<prefix>-slack-notifier`
3. Verify the Secrets Manager secret exists and contains a valid URL:
   ```bash
   aws secretsmanager get-secret-value --secret-id nhs-hometest/slack/hometest-ops-alerts/incoming-webhook
   ```
4. Check SNS subscriptions: `aws sns list-subscriptions-by-topic --topic-arn <topic-arn>` — the Lambda should appear as a subscriber
5. Test with a manual publish:
   ```bash
   aws sns publish --topic-arn <topic-arn> --subject "Test Alert" \
     --message '{"AlarmName":"test","NewStateValue":"ALARM","NewStateReason":"Manual test"}'
   ```

### GitHub Actions Slack notifications not arriving

1. Verify the `SLACK_WEBHOOK_URL` repository secret is set in GitHub → Settings → Secrets and variables → Actions
2. Check the workflow run logs for the `notify-slack` step output
3. Test the webhook manually:
   ```bash
   curl -X POST -H 'Content-type: application/json' --data '{"text":"test"}' <webhook-url>
   ```

### Alarms stuck in INSUFFICIENT_DATA

This typically means the metric has no data points yet. For Lambda metrics, trigger the function at least once. For API Gateway metrics, send a request. The alarm will transition to `OK` once data appears.
