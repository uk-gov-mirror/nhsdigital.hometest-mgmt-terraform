# Lambda Goose Migrator Module

A Terraform module that deploys a Go-based AWS Lambda function for running [Goose](https://github.com/pressly/goose) database migrations against PostgreSQL.

## Overview

This module creates a Lambda function that connects to an Aurora PostgreSQL database and runs SQL migrations using the Goose migration tool. The Lambda is compiled from Go source code and runs on the `provided.al2023` custom runtime for optimal performance.

## Architecture

```text
┌─────────────────────────────────────────────────────────────────┐
│                    Lambda Goose Migrator                         │
├─────────────────────────────────────────────────────────────────┤
│  Runtime: provided.al2023 (custom Go binary)                    │
│  Architecture: arm64                                            │
│  Memory: 128 MB                                                 │
│  Timeout: 300s (5 minutes)                                      │
├─────────────────────────────────────────────────────────────────┤
│  Environment Variables:                                         │
│  - DB_USERNAME: Database username                               │
│  - DB_ADDRESS: Database hostname                                │
│  - DB_PORT: Database port                                       │
│  - DB_NAME: Database name                                       │
│  - DB_SECRET_ARN: Secrets Manager ARN for password              │
└─────────────────────────────────────────────────────────────────┘
           │
           │  VPC (private subnets)
           ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Aurora PostgreSQL                             │
└─────────────────────────────────────────────────────────────────┘
```

## Usage

```hcl
module "goose_migrator" {
  source = "../modules/lambda-goose-migrator"

  db_username        = "postgres"
  db_address         = module.aurora.cluster_endpoint
  db_port            = "5432"
  db_name            = "hometest"
  db_cluster_id      = module.aurora.cluster_id
  subnet_ids         = var.private_subnet_ids
  security_group_ids = [aws_security_group.lambda_rds.id]
}
```

## Inputs

| Name | Description | Type | Required |
|------|-------------|------|----------|
| `db_username` | Database username | `string` | Yes |
| `db_address` | Database hostname/endpoint | `string` | Yes |
| `db_port` | Database port | `string` | Yes |
| `db_name` | Database name | `string` | Yes |
| `db_cluster_id` | Aurora cluster ID (for secret lookup) | `string` | Yes |
| `subnet_ids` | VPC subnet IDs for Lambda | `list(string)` | Yes |
| `security_group_ids` | Security group IDs for Lambda | `list(string)` | Yes |

## Migrations

SQL migrations are stored in `src/migrations/` using Goose naming conventions:

```text
src/migrations/
├── 000001_create_initial_home_test_tables.sql
└── 000002_seed_home_test_data.sql
```

### Migration Format

```sql
-- +goose Up
CREATE TABLE example (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid()
);

-- +goose Down
DROP TABLE example;
```

### Current Schema

The migrations create the HomeTest service database schema:

| Table | Purpose |
|-------|---------|
| `patient_mapping` | Maps NHS numbers to internal patient UIDs |
| `test_type` | Test type codes and descriptions |
| `supplier` | External supplier configuration (Preventx, SH:24) |
| `la_supplier_offering` | Local Authority → Supplier → Test mappings |
| `test_order` | Test orders with auto-generated references |
| `status_type` | Order status codes |
| `order_status` | Order status history |
| `result_type` | Result codes |
| `result_status` | Test result tracking |

## Invocation

Invoke the Lambda to run pending migrations:

```bash
aws lambda invoke \
  --function-name goose-migrator \
  --payload '{}' \
  response.json
```

## Security

- **VPC Access**: Lambda runs within private subnets
- **Secrets Manager**: Database password retrieved at runtime via `DB_SECRET_ARN`
- **IAM**: Least-privilege role with access to RDS, Secrets Manager, and CloudWatch Logs
- **No hardcoded credentials**: All secrets managed via AWS Secrets Manager

## Build Process

The module uses the `terraform-aws-modules/lambda/aws` module with a custom build step:

1. `go mod tidy` — resolves dependencies
2. Cross-compile for `linux/arm64`
3. Package `bootstrap` binary + `migrations/` folder into ZIP

## Related Modules

- [aurora-postgres](../aurora-postgres/) — Aurora PostgreSQL cluster
- [lambda](../lambda/) — Application Lambda functions

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.14.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.37.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | ~> 3.6 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | ~> 6.37.0 |
| <a name="provider_random"></a> [random](#provider\_random) | ~> 3.6 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_goose_migrator_lambda"></a> [goose\_migrator\_lambda](#module\_goose\_migrator\_lambda) | terraform-aws-modules/lambda/aws | 8.7.0 |

## Resources

| Name | Type |
|------|------|
| [aws_iam_policy.lambda_goose_migrator_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_role.lambda_goose_migrator](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.lambda_goose_migrator_attach](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_resourcegroups_group.rg](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/resourcegroups_group) | resource |
| [aws_secretsmanager_secret.app_user](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret_version.app_user](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_version) | resource |
| [random_password.app_user_password](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
| [aws_iam_policy_document.lambda_assume_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.lambda_goose_migrator_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_rds_cluster.db](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/rds_cluster) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_app_user_secret_name"></a> [app\_user\_secret\_name](#input\_app\_user\_secret\_name) | Secrets Manager secret name to store the schema-scoped app\_user credentials | `string` | `""` | no |
| <a name="input_aws_account_id"></a> [aws\_account\_id](#input\_aws\_account\_id) | AWS account ID | `string` | n/a | yes |
| <a name="input_aws_account_shortname"></a> [aws\_account\_shortname](#input\_aws\_account\_shortname) | AWS account short name/alias for resource naming | `string` | n/a | yes |
| <a name="input_aws_allowed_regions"></a> [aws\_allowed\_regions](#input\_aws\_allowed\_regions) | List of AWS regions allowed for resource deployment | `list(string)` | <pre>[<br/>  "eu-west-2",<br/>  "us-east-1"<br/>]</pre> | no |
| <a name="input_aws_region"></a> [aws\_region](#input\_aws\_region) | AWS region for resources | `string` | n/a | yes |
| <a name="input_db_address"></a> [db\_address](#input\_db\_address) | Database address | `string` | n/a | yes |
| <a name="input_db_cluster_id"></a> [db\_cluster\_id](#input\_db\_cluster\_id) | DB CLuster ID | `string` | n/a | yes |
| <a name="input_db_name"></a> [db\_name](#input\_db\_name) | Database name | `string` | n/a | yes |
| <a name="input_db_port"></a> [db\_port](#input\_db\_port) | Database port | `string` | n/a | yes |
| <a name="input_db_schema"></a> [db\_schema](#input\_db\_schema) | Database schema name for environment isolation (e.g., hometest\_dev, hometest\_staging) | `string` | `"public"` | no |
| <a name="input_db_username"></a> [db\_username](#input\_db\_username) | Database username | `string` | n/a | yes |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment name (e.g., dev, staging, prod) | `string` | n/a | yes |
| <a name="input_grant_rds_iam"></a> [grant\_rds\_iam](#input\_grant\_rds\_iam) | Whether to GRANT rds\_iam to the app\_user so that app lambdas can use IAM token authentication. Independent of how the migrator itself connects. | `bool` | `false` | no |
| <a name="input_project_name"></a> [project\_name](#input\_project\_name) | Project name used for resource naming | `string` | n/a | yes |
| <a name="input_security_group_ids"></a> [security\_group\_ids](#input\_security\_group\_ids) | List of security group IDs for Lambda VPC config | `list(string)` | n/a | yes |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | List of subnet IDs for Lambda VPC config | `list(string)` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags for all resources | `map(string)` | `{}` | no |
| <a name="input_use_iam_auth"></a> [use\_iam\_auth](#input\_use\_iam\_auth) | Whether the goose migrator Lambda itself connects to Aurora using IAM auth instead of Secrets Manager password. The master user typically uses password auth, so this is usually false. | `bool` | `false` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_app_user_secret_arn"></a> [app\_user\_secret\_arn](#output\_app\_user\_secret\_arn) | ARN of the Secrets Manager secret containing app\_user credentials |
| <a name="output_app_user_secret_name"></a> [app\_user\_secret\_name](#output\_app\_user\_secret\_name) | Name of the Secrets Manager secret containing app\_user credentials |
| <a name="output_app_username"></a> [app\_username](#output\_app\_username) | The database username for the schema-scoped app\_user |
| <a name="output_function_arn"></a> [function\_arn](#output\_function\_arn) | ARN of the Lambda function |
| <a name="output_function_name"></a> [function\_name](#output\_function\_name) | Name of the Lambda function for invocation |
<!-- END_TF_DOCS -->
