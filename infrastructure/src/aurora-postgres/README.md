# aurora-postgres

## Overview

This module deploys an Aurora PostgreSQL instance in the VPC and data subnets created by the `network` module.

**Important:** This module depends on the network module being deployed first. It uses Terraform remote state to reference:
- VPC ID from `data.terraform_remote_state.network.outputs.vpc_id`
- Data subnet IDs from `data.terraform_remote_state.network.outputs.data_subnet_ids`

## Prerequisites

1. Deploy the `network` module first
2. Ensure the network module's Terraform state is stored in S3
3. Set `create_db_subnet_group = true` in the network module (default)
4. Provide the `terraform_state_bucket` variable to this module

## Usage

```hcl
module "aurora_postgres" {
  source = "./src/aurora-postgres"

  # Required variables
  aws_region            = "eu-west-2"
  aws_account_id        = "123456789012"
  aws_account_shortname = "poc"
  project_name          = "hometest"
  environment           = "core"

  # Terraform state bucket (for network module reference)
  terraform_state_bucket = "my-terraform-state-bucket"

  # Database configuration
  instance_class    = "db.t4g.micro"
  allocated_storage = 20
  multi_az          = false

  # Security
  allowed_security_group_ids = [module.network.lambda_security_group_id]
}
```

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.14.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.37.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | ~> 6.37.0 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_aurora_alarms"></a> [aurora\_alarms](#module\_aurora\_alarms) | ../../modules/aurora-alarms | n/a |
| <a name="module_aurora_postgres"></a> [aurora\_postgres](#module\_aurora\_postgres) | ../../modules/aurora-postgres | n/a |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_resourcegroups_group.rg](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/resourcegroups_group) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_allowed_cidr_blocks"></a> [allowed\_cidr\_blocks](#input\_allowed\_cidr\_blocks) | List of CIDR blocks allowed to connect to the database | `list(string)` | `[]` | no |
| <a name="input_allowed_security_group_ids"></a> [allowed\_security\_group\_ids](#input\_allowed\_security\_group\_ids) | List of security group IDs allowed to connect to the database | `list(string)` | `[]` | no |
| <a name="input_apply_immediately"></a> [apply\_immediately](#input\_apply\_immediately) | Specifies whether any database modifications are applied immediately | `bool` | `false` | no |
| <a name="input_aws_account_id"></a> [aws\_account\_id](#input\_aws\_account\_id) | AWS account ID | `string` | n/a | yes |
| <a name="input_aws_account_shortname"></a> [aws\_account\_shortname](#input\_aws\_account\_shortname) | AWS account short name/alias for resource naming | `string` | n/a | yes |
| <a name="input_aws_allowed_regions"></a> [aws\_allowed\_regions](#input\_aws\_allowed\_regions) | List of AWS regions allowed for resource deployment | `list(string)` | <pre>[<br/>  "eu-west-2",<br/>  "us-east-1"<br/>]</pre> | no |
| <a name="input_aws_region"></a> [aws\_region](#input\_aws\_region) | AWS region for resources | `string` | n/a | yes |
| <a name="input_backup_retention_period"></a> [backup\_retention\_period](#input\_backup\_retention\_period) | The days to retain backups for | `number` | `7` | no |
| <a name="input_backup_window"></a> [backup\_window](#input\_backup\_window) | The daily time range during which automated backups are created | `string` | `"03:00-04:00"` | no |
| <a name="input_db_name"></a> [db\_name](#input\_db\_name) | The name of the database to create when the DB instance is created | `string` | `"postgres"` | no |
| <a name="input_db_subnet_group_name"></a> [db\_subnet\_group\_name](#input\_db\_subnet\_group\_name) | Name of the DB subnet group to use for the Aurora cluster. If not provided, the module will attempt to create one. | `string` | `null` | no |
| <a name="input_deletion_protection"></a> [deletion\_protection](#input\_deletion\_protection) | If the DB instance should have deletion protection enabled | `bool` | `false` | no |
| <a name="input_enable_http_endpoint"></a> [enable\_http\_endpoint](#input\_enable\_http\_endpoint) | Enable the Data API for Aurora Serverless v2. Allows querying the database from AWS Console without managing connections. | `bool` | `false` | no |
| <a name="input_enable_iam_auth"></a> [enable\_iam\_auth](#input\_enable\_iam\_auth) | Enable IAM database authentication for the Aurora cluster | `bool` | `false` | no |
| <a name="input_enable_ok_actions"></a> [enable\_ok\_actions](#input\_enable\_ok\_actions) | Send notifications when alarms return to OK state (enable for prod, disable for dev to reduce noise) | `bool` | `false` | no |
| <a name="input_engine_version"></a> [engine\_version](#input\_engine\_version) | PostgreSQL engine version | `string` | `"17.9"` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment name (e.g., dev, staging, prod) | `string` | n/a | yes |
| <a name="input_kms_key_id"></a> [kms\_key\_id](#input\_kms\_key\_id) | The ARN for the KMS encryption key | `string` | `""` | no |
| <a name="input_maintenance_window"></a> [maintenance\_window](#input\_maintenance\_window) | The window to perform maintenance in | `string` | `"Mon:04:00-Mon:05:00"` | no |
| <a name="input_master_user_secret_kms_key_id"></a> [master\_user\_secret\_kms\_key\_id](#input\_master\_user\_secret\_kms\_key\_id) | The ARN of the KMS key used to encrypt the master user password secret in Secrets Manager | `string` | `null` | no |
| <a name="input_number_of_instances"></a> [number\_of\_instances](#input\_number\_of\_instances) | Number of Aurora instances to create in the cluster | `number` | `1` | no |
| <a name="input_project_name"></a> [project\_name](#input\_project\_name) | Project name used for resource naming | `string` | n/a | yes |
| <a name="input_publicly_accessible"></a> [publicly\_accessible](#input\_publicly\_accessible) | Whether the database should be publicly accessible | `bool` | `false` | no |
| <a name="input_serverlessv2_max_capacity"></a> [serverlessv2\_max\_capacity](#input\_serverlessv2\_max\_capacity) | Maximum Aurora capacity units (ACUs) for Aurora Serverless v2 | `number` | `4` | no |
| <a name="input_serverlessv2_min_capacity"></a> [serverlessv2\_min\_capacity](#input\_serverlessv2\_min\_capacity) | Minimum Aurora capacity units (ACUs) for Aurora Serverless v2 | `number` | `0.5` | no |
| <a name="input_skip_final_snapshot"></a> [skip\_final\_snapshot](#input\_skip\_final\_snapshot) | Determines whether a final DB snapshot is created before the DB instance is deleted | `bool` | `false` | no |
| <a name="input_sns_alerts_critical_topic_arn"></a> [sns\_alerts\_critical\_topic\_arn](#input\_sns\_alerts\_critical\_topic\_arn) | ARN of the critical alerts SNS topic (from shared\_services). When set, creates CloudWatch alarms. | `string` | `null` | no |
| <a name="input_storage_encrypted"></a> [storage\_encrypted](#input\_storage\_encrypted) | Specifies whether the DB instance is encrypted | `bool` | `true` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags for all resources | `map(string)` | `{}` | no |
| <a name="input_username"></a> [username](#input\_username) | Username for the master DB user | `string` | `"postgres"` | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC ID from network module (passed via Terragrunt dependency) | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_cluster_arn"></a> [cluster\_arn](#output\_cluster\_arn) | The Amazon RDS Aurora cluster ARN |
| <a name="output_cluster_database_name"></a> [cluster\_database\_name](#output\_cluster\_database\_name) | The database name in the Aurora cluster |
| <a name="output_cluster_endpoint"></a> [cluster\_endpoint](#output\_cluster\_endpoint) | The writer endpoint of the Aurora cluster |
| <a name="output_cluster_hosted_zone_id"></a> [cluster\_hosted\_zone\_id](#output\_cluster\_hosted\_zone\_id) | The canonical hosted zone ID of the Aurora cluster (for Route 53 Alias) |
| <a name="output_cluster_id"></a> [cluster\_id](#output\_cluster\_id) | The Amazon RDS Aurora cluster ID |
| <a name="output_cluster_master_user_secret_arn"></a> [cluster\_master\_user\_secret\_arn](#output\_cluster\_master\_user\_secret\_arn) | The ARN of the Secrets Manager secret for the Aurora master user password |
| <a name="output_cluster_master_user_secret_name"></a> [cluster\_master\_user\_secret\_name](#output\_cluster\_master\_user\_secret\_name) | The Secrets Manager secret name for the Aurora master user password |
| <a name="output_cluster_master_username"></a> [cluster\_master\_username](#output\_cluster\_master\_username) | The master username for the Aurora cluster |
| <a name="output_cluster_port"></a> [cluster\_port](#output\_cluster\_port) | The port the Aurora cluster listens on |
| <a name="output_cluster_resource_id"></a> [cluster\_resource\_id](#output\_cluster\_resource\_id) | The RDS cluster resource ID, used for IAM authentication ARNs |
| <a name="output_connection_string"></a> [connection\_string](#output\_connection\_string) | Aurora PostgreSQL connection string (without password) |
| <a name="output_vpc_id"></a> [vpc\_id](#output\_vpc\_id) | The ID of the VPC |
<!-- END_TF_DOCS -->
