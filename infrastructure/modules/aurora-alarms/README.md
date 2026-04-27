# Aurora Alarms Module

CloudWatch alarms for monitoring AWS Aurora PostgreSQL Serverless v2 database clusters.

## Features

- **CPU & Memory**: High CPU utilization and low freeable memory alarms
- **Connection Monitoring**: Alerts when database connections exceed threshold
- **Deadlock Detection**: Immediate alerting on any deadlock occurrence
- **Replica Lag**: Optional alarm for Aurora replica replication lag
- **Serverless Capacity**: ACU usage monitoring for Serverless v2 clusters
- **Storage Monitoring**: Low free local storage alarm

## Usage

```hcl
module "aurora_alarms" {
  source = "../../modules/aurora-alarms"

  project_name          = "nhs-hometest"
  aws_account_shortname = "prod"
  environment           = "prod"
  cluster_identifier    = module.aurora.cluster_identifier

  alarm_actions     = [module.alerts_topic.topic_arn]
  enable_ok_actions = true

  alarm_cpu_threshold              = 80
  alarm_freeable_memory_threshold_mb = 256
  alarm_max_connections_threshold  = 100
  alarm_max_capacity_threshold     = 8

  # Enable if using read replicas
  create_replica_lag_alarm       = true
  alarm_replica_lag_threshold_ms = 100

  tags = {
    Owner = "platform-team"
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| project_name | Name of the project | `string` | n/a | yes |
| aws_account_shortname | AWS account short name for naming | `string` | n/a | yes |
| environment | Environment name | `string` | n/a | yes |
| cluster_identifier | Aurora DB cluster identifier | `string` | n/a | yes |
| alarm_actions | SNS topic ARNs for notifications | `list(string)` | `[]` | no |
| enable_ok_actions | Send notifications on OK state | `bool` | `false` | no |
| alarm_period | Evaluation period in seconds | `number` | `300` | no |
| alarm_evaluation_periods | Consecutive periods before triggering | `number` | `2` | no |
| alarm_cpu_threshold | CPU utilization percentage threshold | `number` | `80` | no |
| alarm_freeable_memory_threshold_mb | Memory threshold in MB (triggers when below) | `number` | `256` | no |
| alarm_max_connections_threshold | Maximum connections threshold | `number` | `100` | no |
| create_replica_lag_alarm | Create replica lag alarm (only if replicas exist) | `bool` | `false` | no |
| alarm_replica_lag_threshold_ms | Replica lag threshold in milliseconds | `number` | `100` | no |
| alarm_max_capacity_threshold | Max ACU threshold for Serverless v2 | `number` | `8` | no |
| alarm_free_storage_threshold_gb | Free storage threshold in GB (triggers when below) | `number` | `5` | no |
| tags | Additional tags | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| alarm_cpu_arn | ARN of CPU utilization alarm |
| alarm_memory_arn | ARN of memory alarm |
| alarm_connections_arn | ARN of connections alarm |
| alarm_deadlocks_arn | ARN of deadlocks alarm |
| alarm_replica_lag_arn | ARN of replica lag alarm (null if not created) |
| alarm_capacity_arn | ARN of capacity alarm |
| alarm_storage_arn | ARN of storage alarm |

## Best Practices

1. Set `alarm_evaluation_periods` to 2+ to avoid transient spikes triggering false alarms.
2. Only enable the replica lag alarm when read replicas are provisioned.
3. Adjust `alarm_max_capacity_threshold` to match your Serverless v2 max ACU configuration.
4. Lower memory and storage thresholds for production to get earlier warnings.
