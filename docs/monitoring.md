Based on my thorough scan of the repository, here's what I found and recommend:

## Current State

**Existing alerting** is minimal:

- SNS topic publishing to `england.HomeTestInfraAdmins@nhs.net` (email only)
- SQS alarms for queue age, depth, and DLQ depth
- Lambda CloudWatch logs with X-Ray tracing
- Container Insights on ECS

**No Slack integration exists** — no webhooks, no AWS Chatbot, no SNS-to-Slack Lambda.

---

## Recommended Alerts to Add

### Lambda (10 functions per env — critical)

| Alert | Metric | Threshold | Priority |
|-------|--------|-----------|----------|
| Lambda Errors | `Errors` | > 0 for 1 min | **P1** |
| Lambda Throttles | `Throttles` | > 0 for 1 min | **P1** |
| Lambda Duration High | `Duration` p99 | > 80% of timeout | **P2** |
| Lambda Concurrent Executions | `ConcurrentExecutions` | > 80% reserved concurrency | **P2** |
| Lambda Iterator Age (SQS-triggered) | `IteratorAge` | > 60s for `order-router-lambda` | **P1** |

### API Gateway

| Alert | Metric | Threshold | Priority |
|-------|--------|-----------|----------|
| 5XX Error Rate | `5XXError` | > 1% of requests | **P1** |
| 4XX Error Rate | `4XXError` | > 10% of requests | **P2** |
| Latency High | `Latency` p99 | > 3s | **P2** |
| Integration Latency | `IntegrationLatency` p99 | > 2s | **P2** |

### Aurora PostgreSQL Serverless v2

| Alert | Metric | Threshold | Priority |
|-------|--------|-----------|----------|
| CPU Utilisation | `CPUUtilization` | > 80% for 5 min | **P2** |
| Freeable Memory Low | `FreeableMemory` | < 256MB | **P2** |
| DB Connections High | `DatabaseConnections` | > 80% max | **P1** |
| Deadlocks | `Deadlocks` | > 0 | **P1** |
| Replication Lag | `AuroraReplicaLag` | > 100ms | **P2** |
| ServerlessDatabaseCapacity | `ServerlessDatabaseCapacity` | > 80% max ACU | **P2** |

### SQS (enhance existing)

| Alert | Metric | Threshold | Priority |
|-------|--------|-----------|----------|
| **DLQ Non-Empty** (already exists) | `ApproximateNumberOfMessagesVisible` | > 0 on any DLQ | **P1** |
| Order Placement Queue Backlog | `ApproximateNumberOfMessagesVisible` | > 100 on `order-placement` | **P1** |
| Notifications FIFO Stuck | `ApproximateAgeOfOldestMessage` | > 300s on `notifications` | **P1** |

### WAF

| Alert | Metric | Threshold | Priority |
|-------|--------|-----------|----------|
| Rate Limit Triggered | `BlockedRequests` (rate-limit rule) | > 0 | **P2** |
| WAF Blocked Spike | `BlockedRequests` (all rules) | > 100/min | **P2** |
| SQL Injection Detected | `BlockedRequests` (SQLi rule) | > 0 | **P1** |

### CloudFront (SPA)

| Alert | Metric | Threshold | Priority |
|-------|--------|-----------|----------|
| 5XX Error Rate | `5xxErrorRate` | > 1% | **P1** |
| Origin Latency High | `OriginLatency` p99 | > 5s | **P2** |
| Cache Hit Rate Low | `CacheHitRate` | < 50% | **P3** |

### Route53 Health Checks

| Alert | Metric | Threshold | Priority |
|-------|--------|-----------|----------|
| Endpoint Health | `HealthCheckStatus` | unhealthy | **P1** |

### Network Firewall

| Alert | Metric | Threshold | Priority |
|-------|--------|-----------|----------|
| Dropped Packets | `DroppedPackets` | > 100/min | **P2** |

### NAT Gateway

| Alert | Metric | Threshold | Priority |
|-------|--------|-----------|----------|
| Error Port Allocation | `ErrorPortAllocation` | > 0 | **P2** |
| Packets Drop Count | `PacketsDropCount` | > 0 for 5 min | **P2** |

---

## Slack Notification Strategy

### Recommended: AWS Chatbot + SNS

The cleanest approach for this stack:

```bash
CloudWatch Alarm → SNS Topic → AWS Chatbot → Slack Channel
```

### Suggested Slack Channels & Routing

| Channel | What Gets Sent | Priority |
|---------|---------------|----------|
| `#hometest-alerts-critical` | P1 alerts (Lambda errors, DLQ messages, 5xx spikes, DB deadlocks, health check failures) | Immediate |
| `#hometest-alerts-warning` | P2 alerts (high latency, capacity warnings, WAF blocks) | During hours |
| `#hometest-deployments` | GitHub Actions deploy success/failure via workflow notification step | Informational |
| `#hometest-security` | WAF SQL injection blocks, rate limiting triggers, unusual blocked request spikes | Review |

### Implementation Approach

1. **Create a Terraform module** `modules/slack-alerts/` using `aws_chatbot_slack_channel_configuration`
2. **Create tiered SNS topics**: `alerts-critical`, `alerts-warning`, `alerts-security`
3. **Route alarms** to the appropriate SNS topic by severity
4. **Add a GitHub Actions step** to post deploy status to `#hometest-deployments` using a Slack webhook

### What to Notify on Slack (not email)

| Event | Channel |
|-------|---------|
| Any DLQ receives a message | critical |
| Lambda error rate > 0 in prod | critical |
| API Gateway 5XX in prod | critical |
| Aurora DB connections > 80% | critical |
| Deployment succeeded/failed | deployments |
| WAF SQLi or rate-limit block | security |
| High latency (API or Lambda) | warning |
| SQS backlog growing | warning |
| Certificate expiry < 30 days | warning |

---

## Quick Wins (highest value, lowest effort)

1. **Lambda error alarms** — you have 10 Lambdas with zero error alerting
2. **API Gateway 5xx alarm** — customer-facing, currently invisible
3. **DLQ alerts to Slack** — DLQ alarms exist but only email; Slack gives faster response
4. **Aurora connection/CPU alarms** — shared DB, single point of failure
5. **GitHub Actions deploy notification** — one workflow step addition

Want me to implement any of these as Terraform modules/resources?


All changes are in place. Here's a complete summary of everything that was created and modified:

---

## Summary of Changes

### New Modules Created (6)

| Module | Location | Purpose |
|--------|----------|---------|
| **slack-alerts** | modules/slack-alerts/ | AWS Chatbot → Slack channel integration |
| **api-gateway-alarms** | modules/api-gateway-alarms/ | 5XX, 4XX, latency, integration latency per API |
| **aurora-alarms** | modules/aurora-alarms/ | CPU, memory, connections, deadlocks, capacity, storage |
| **waf-alarms** | modules/waf-alarms/ | Blocked request spikes, rate limiting, SQLi detection |
| **cloudfront-alarms** | modules/cloudfront-alarms/ | 5XX, 4XX, origin latency |
| **network-alarms** | modules/network-alarms/ | NAT Gateway port allocation/packet drops, firewall dropped packets |

### Enhanced Existing Module

- **lambda module** (modules/lambda/main.tf) — Added **throttle**, **duration (p99 vs timeout)**, and **concurrent executions** alarms alongside existing error alarm

### Tiered SNS Topics (shared_services)

| Topic | Routing | Slack Channel |
|-------|---------|---------------|
| `alerts-critical` | Lambda errors, DLQ, 5XX, deadlocks | `#hometest-alerts-critical` |
| `alerts-warning` | High latency, capacity, NAT/firewall | `#hometest-alerts-warning` |
| `alerts-security` | WAF SQLi, rate limiting, blocked spikes | `#hometest-alerts-security` |

### Wiring By Layer

| Layer | File | What's wired |
|-------|------|-------------|
| **shared_services** | sns.tf | 3 new SNS topics + Slack Chatbot |
| **shared_services** | alarms_waf.tf | Regional + CloudFront WAF alarms → security topic |
| **shared_services** | alarms_network.tf | NAT GW + firewall alarms → warning topic |
| **aurora-postgres** | alarms.tf | All DB alarms → critical topic |
| **hometest-app** | alarms.tf | API Gateway + CloudFront alarms → critical topic |
| **hometest-app** | lambda.tf | Lambda error/throttle/duration alarms → critical topic |
| **hometest-app** | sqs.tf | SQS DLQ/age/depth alarms → critical topic |

### GitHub Actions Slack Notifications

- Created .github/actions/notify-slack/action.yaml composite action
- Added notification job to cicd-3-deploy.yaml
- Added notification step to deploy-tf-hometest-app.yaml summary job

### Setup Required

To activate Slack integration:
1. Authorize Slack workspace in **AWS Chatbot console** (one-time)
2. Set these Terragrunt variables for shared_services:
   - `enable_slack_alerts = true`
   - `slack_workspace_id = "T0XXXXXXX"`
   - `slack_channel_id_critical`, `slack_channel_id_warning`, `slack_channel_id_security`
3. Set **`SLACK_DEPLOYMENTS_WEBHOOK_URL`** as a GitHub Actions repository variable for deploy notifications
