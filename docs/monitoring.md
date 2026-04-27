# HomeTest Monitoring & Alerting

This document describes the monitoring, alerting, and notification infrastructure for NHS HomeTest.

## Architecture Overview

```bash
CloudWatch Alarms → SNS Topics (tiered) → AWS Chatbot → Slack (#hometest-ops-alerts)
                                        → Email subscriptions
GitHub Actions    → Slack Webhook (secret) → #hometest-ops-alerts
```

All CloudWatch alarms publish to one of three tiered SNS topics in `shared_services`. AWS Chatbot subscribes to each topic and forwards formatted messages to the configured Slack channel.

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

### Infrastructure Alerts (SNS → AWS Chatbot → Slack)

- **Module**: [`infrastructure/modules/slack-alerts`](../infrastructure/modules/slack-alerts/README.md)
- **Deployed in**: `shared_services` layer
- **Mechanism**: AWS Chatbot Slack channel configurations subscribe to SNS topics and post formatted alarm messages to Slack
- **Slack channel**: `#hometest-ops-alerts` (all tiers currently routed to one channel)

AWS Chatbot natively renders CloudWatch alarm details including alarm name, state, reason, metric, and account context.

#### Prerequisites

1. **Authorize the Slack workspace** in the [AWS Chatbot console](https://console.aws.amazon.com/chatbot/) — this is a **one-time manual step** per AWS account + Slack workspace
2. Obtain the **Slack workspace ID** (`T0XXXXXXX`) and **channel ID(s)** (`C0XXXXXXX`) — right-click the channel in Slack → View channel details → copy the ID at the bottom

#### Terragrunt Configuration

```hcl
# infrastructure/environments/<account>/core/shared_services/terragrunt.hcl
inputs = {
  enable_slack_alerts       = true
  slack_workspace_id        = "T0XXXXXXX"          # Slack workspace (team) ID
  slack_channel_id_critical = "C0XXXXXXX"           # Channel for critical alerts
  slack_channel_id_warning  = "C0XXXXXXX"           # Channel for warning alerts (same channel for now)
  slack_channel_id_security = "C0XXXXXXX"           # Channel for security alerts (same channel for now)
}
```

To disable Slack alerts for an environment, set `enable_slack_alerts = false`. Email alerts continue independently.

#### Splitting Channels (Future)

All three severity tiers currently point to the same channel (`#hometest-ops-alerts`). To split by severity, create additional Slack channels and set distinct channel IDs for each `slack_channel_id_*` variable.

### Deployment Notifications (GitHub Actions → Webhook)

- **Action**: `.github/actions/notify-slack`
- **Secret**: `SLACK_WEBHOOK_URL` (GitHub Actions repository secret)
- **Triggers**: End of `cicd-deploy-poc`, `cicd-deploy-dev`, `deploy-hometest-app`, and `deploy-demo` workflows
- **Content**: Deployment status (success/failure/cancelled), environment, module, actor, and a link to the run

---

## CloudWatch Alarms by Layer

### shared_services

#### WAF Alarms ([`modules/waf-alarms`](../infrastructure/modules/waf-alarms/README.md))

| Alarm | Metric | Threshold | Severity |
|---|---|---|---|
| Blocked Request Spike | BlockedRequests | > 100 in 5 min | Security |
| Rate Limit Triggered | RateLimitRule count | > 0 in 5 min | Security |
| SQLi Detected | SQLiRule count | > 0 in 5 min | Security |

Applied to both the regional WAF (API Gateway/ALB) and CloudFront WAF.

> **Note**: CloudFront WAF alarms are created in **us-east-1** via `providers = { aws = aws.us_east_1 }` because CloudFront WAF metrics are published there.

#### Network Alarms ([`modules/network-alarms`](../infrastructure/modules/network-alarms/README.md))

| Alarm | Metric | Threshold | Severity |
|---|---|---|---|
| NAT GW Port Allocation Errors | ErrorPortAllocation | > 0 in 5 min | Warning |
| NAT GW Packets Dropped | PacketsDropCount | > 100 in 5 min | Warning |
| Network Firewall Dropped Packets | DroppedPackets | > 100 in 5 min | Warning |

NAT Gateway alarms are created per gateway via `for_each`.

### aurora-postgres

#### Aurora Alarms ([`modules/aurora-alarms`](../infrastructure/modules/aurora-alarms/README.md))

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

#### Lambda Alarms (built into [`modules/lambda`](../infrastructure/modules/lambda/README.md))

Each Lambda function gets these alarms automatically:

| Alarm | Metric | Threshold | Severity |
|---|---|---|---|
| Errors | Errors | ≥ 1 sum in 1 min | Critical |
| Throttles | Throttles | ≥ 1 sum in 1 min | Critical |
| Duration (p99) | Duration (p99) | ≥ timeout × 80% | Critical |
| Concurrent Executions | ConcurrentExecutions | ≥ reserved × 80% | Critical |
| Logged Errors | Custom metric (CloudWatch Logs metric filter) | ≥ 5 sum in 5 min | Critical |

The concurrency alarm is only created when `reserved_concurrent_executions > 0`.

The **Logged Errors** alarm uses a CloudWatch Logs metric filter to catch errors that are logged (e.g. `console.error`, caught exceptions) but don't fail the Lambda invocation. The filter matches `?ERROR ?Error ?Exception ?errorType` patterns.

#### SQS Alarms (built into [`modules/sqs`](../infrastructure/modules/sqs/README.md))

Each SQS queue gets an `ApproximateAgeOfOldestMessage` alarm. The following queues are monitored:

- `order-placement`
- `order-result`
- `order-notification`
- `order-eviction`
- `supplier-notification`

Each queue also has a dead-letter queue (DLQ) with its own age alarm.

#### API Gateway Alarms ([`modules/api-gateway-alarms`](../infrastructure/modules/api-gateway-alarms/README.md))

| Alarm | Metric | Threshold | Severity |
|---|---|---|---|
| 5XX Error Rate | 5XXError / Count × 100 | > 1% in 5 min | Critical |
| 4XX Error Rate | 4XXError / Count × 100 | > 10% in 5 min | Critical |
| Latency (p99) | Latency (p99) | > 3000 ms in 5 min | Critical |
| Integration Latency (p99) | IntegrationLatency (p99) | > 2000 ms in 5 min | Critical |

#### CloudFront Alarms ([`modules/cloudfront-alarms`](../infrastructure/modules/cloudfront-alarms/README.md))

| Alarm | Metric | Threshold | Severity |
|---|---|---|---|
| 5XX Error Rate | 5xxErrorRate | > 1% in 5 min | Critical |
| 4XX Error Rate | 4xxErrorRate | > 10% in 5 min | Critical |
| Origin Latency (p99) | OriginLatency (p99) | > 5000 ms in 5 min | Critical |

> **Note**: CloudFront alarms are created in **us-east-1** via `providers = { aws = aws.us_east_1 }` because CloudFront metrics are published there.

---

## Threshold Tuning

All alarm thresholds are configurable via module variables. Default values are chosen for a typical workload and should be reviewed per environment:

- **POC/Dev**: Defaults are usually fine; consider relaxing to avoid noise during development.
- **Production**: Review thresholds against actual traffic patterns. Tighten error rate thresholds and shorten evaluation periods.

To override a threshold, set the corresponding variable in the terragrunt inputs for the relevant layer.

### OK Actions (Recovery Notifications)

By default, alarms do **not** send notifications when returning to OK state (`enable_ok_actions = false`). This reduces noise in dev/POC environments where alarms may fire on first deploy before metrics exist.

To enable recovery notifications (recommended for production):

```hcl
# In terragrunt inputs for each layer (shared_services, hometest-app, aurora-postgres)
enable_ok_actions = true
```

This is configured per-layer so you can enable it selectively (e.g. prod only).

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

1. Verify the Slack workspace is authorized in the [AWS Chatbot console](https://console.aws.amazon.com/chatbot/)
2. Check the Chatbot channel configuration exists: `aws chatbot describe-slack-channel-configurations`
3. Verify the workspace ID and channel ID match your Slack workspace/channel
4. Check SNS subscriptions: `aws sns list-subscriptions-by-topic --topic-arn <topic-arn>` — Chatbot should appear as a subscriber
5. Check the Chatbot CloudWatch log group for errors (logging level must be `INFO` or `ERROR`)
6. Test with a manual publish:

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
