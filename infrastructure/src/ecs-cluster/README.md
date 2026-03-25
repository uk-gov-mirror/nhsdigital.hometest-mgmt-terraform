# ecs-cluster

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.14.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.33.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | ~> 6.33.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_cloudwatch_log_group.ecs_exec](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_cloudwatch_log_group.ecs_tasks](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_ecs_cluster.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_cluster) | resource |
| [aws_ecs_cluster_capacity_providers.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_cluster_capacity_providers) | resource |
| [aws_security_group.ecs_tasks](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_service_discovery_private_dns_namespace.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/service_discovery_private_dns_namespace) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_aws_account_id"></a> [aws\_account\_id](#input\_aws\_account\_id) | AWS account ID | `string` | n/a | yes |
| <a name="input_aws_account_shortname"></a> [aws\_account\_shortname](#input\_aws\_account\_shortname) | AWS account short name for resource naming | `string` | n/a | yes |
| <a name="input_aws_region"></a> [aws\_region](#input\_aws\_region) | AWS region for resources | `string` | n/a | yes |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment name | `string` | n/a | yes |
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | ARN of KMS key for encryption | `string` | n/a | yes |
| <a name="input_log_retention_days"></a> [log\_retention\_days](#input\_log\_retention\_days) | CloudWatch log retention in days | `number` | `30` | no |
| <a name="input_project_name"></a> [project\_name](#input\_project\_name) | Name of the project | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to all resources | `map(string)` | `{}` | no |
| <a name="input_vpc_cidr"></a> [vpc\_cidr](#input\_vpc\_cidr) | VPC CIDR block for security group rules | `string` | n/a | yes |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC ID for ECS cluster resources | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_cluster_arn"></a> [cluster\_arn](#output\_cluster\_arn) | ARN of the ECS cluster |
| <a name="output_cluster_id"></a> [cluster\_id](#output\_cluster\_id) | ID of the ECS cluster |
| <a name="output_cluster_name"></a> [cluster\_name](#output\_cluster\_name) | Name of the ECS cluster |
| <a name="output_ecs_tasks_log_group_arn"></a> [ecs\_tasks\_log\_group\_arn](#output\_ecs\_tasks\_log\_group\_arn) | ARN of the CloudWatch log group for ECS tasks |
| <a name="output_ecs_tasks_log_group_name"></a> [ecs\_tasks\_log\_group\_name](#output\_ecs\_tasks\_log\_group\_name) | Name of the CloudWatch log group for ECS tasks |
| <a name="output_ecs_tasks_security_group_id"></a> [ecs\_tasks\_security\_group\_id](#output\_ecs\_tasks\_security\_group\_id) | ID of the shared ECS tasks baseline security group |
| <a name="output_service_discovery_namespace_arn"></a> [service\_discovery\_namespace\_arn](#output\_service\_discovery\_namespace\_arn) | ARN of the Cloud Map service discovery namespace |
| <a name="output_service_discovery_namespace_id"></a> [service\_discovery\_namespace\_id](#output\_service\_discovery\_namespace\_id) | ID of the Cloud Map service discovery namespace |
| <a name="output_service_discovery_namespace_name"></a> [service\_discovery\_namespace\_name](#output\_service\_discovery\_namespace\_name) | Name of the Cloud Map service discovery namespace |
<!-- END_TF_DOCS -->
