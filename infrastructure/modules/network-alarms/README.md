# Network Alarms Module

CloudWatch alarms for monitoring network infrastructure health including NAT Gateways and AWS Network Firewall.

## Features

- **NAT Gateway Monitoring**: Port allocation error and packet drop alarms per gateway
- **Network Firewall**: Optional alarm for stateful engine dropped packets
- **Multi-Gateway Support**: Dynamically creates alarm sets for each NAT Gateway in the map

## Usage

```hcl
module "network_alarms" {
  source = "../../modules/network-alarms"

  project_name          = "nhs-hometest"
  aws_account_shortname = "prod"
  environment           = "prod"

  nat_gateway_ids = {
    az1 = "nat-0abc123def456"
    az2 = "nat-0def789ghi012"
  }

  # Optional Network Firewall monitoring
  firewall_name = "prod-network-firewall"

  alarm_actions     = [module.alerts_topic.topic_arn]
  enable_ok_actions = true

  alarm_nat_packets_drop_threshold  = 100
  alarm_firewall_dropped_threshold  = 100

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
| nat_gateway_ids | Map of logical name to NAT Gateway ID | `map(string)` | `{}` | no |
| firewall_name | Network Firewall name (null to skip firewall alarms) | `string` | `null` | no |
| alarm_actions | SNS topic ARNs for notifications | `list(string)` | `[]` | no |
| enable_ok_actions | Send notifications on OK state | `bool` | `false` | no |
| alarm_period | Evaluation period in seconds | `number` | `300` | no |
| alarm_evaluation_periods | Consecutive periods before triggering | `number` | `2` | no |
| alarm_nat_packets_drop_threshold | NAT packet drop threshold | `number` | `100` | no |
| alarm_firewall_dropped_threshold | Network Firewall packet drop threshold | `number` | `100` | no |
| tags | Additional tags | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| alarm_nat_port_allocation_arns | Map of NAT Gateway name to port allocation error alarm ARN |
| alarm_nat_packets_drop_arns | Map of NAT Gateway name to packet drop alarm ARN |
| alarm_firewall_dropped_arn | ARN of Network Firewall dropped packets alarm (null if not created) |

## Best Practices

1. Use meaningful keys in `nat_gateway_ids` (e.g., AZ names) for clear alarm naming.
2. Port allocation errors always trigger on any occurrence — investigate immediately as they indicate SNAT exhaustion.
3. Tune packet drop thresholds based on expected traffic volume.
4. Enable firewall alarms in production to detect potential security incidents or misconfigured rules.
