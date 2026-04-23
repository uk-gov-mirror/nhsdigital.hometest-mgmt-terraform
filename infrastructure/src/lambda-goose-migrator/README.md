# Lambda Goose Migrator Module

A Terraform module that deploys a Go-based AWS Lambda function for running [Goose](https://github.com/pressly/goose) database migrations against PostgreSQL.

## Overview

This module manages the **infrastructure** for the goose migrator Lambda: IAM role, VPC config, environment variables, and invocation hooks. The Lambda source code (Go) and SQL migrations live in [hometest-service](https://github.com/NHSDigital/hometest-service) under `lambdas/goose-migrator-lambda/`, which is the source of truth.

The ZIP artifact is built from the service repo before each Terraform plan/apply via a Terragrunt `before_hook` and consumed here via the `goose_migrator_zip_path` variable.

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
│  Actions:                                                       │
│  - migrate  : create schema/user, run goose.Up, re-grant privs  │
│  - teardown : drop schema (CASCADE) and app_user role           │
└─────────────────────────────────────────────────────────────────┘
           │
           │  VPC (private subnets)
           ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Aurora PostgreSQL                            │└─────────────────────────────────────────────────────────────────┘
```

## Source of Truth

All of the following live in **hometest-service**, not this repo:

- Go Lambda source (`src/main.go`, `src/go.mod`)
- SQL migrations (`migrations/000001_*.sql` … `000016_*.sql`)
- Build script (`scripts/build.sh`)
- Migration integration tests (`scripts/test-migrations.sh`)

To add a new migration, add a file to `lambdas/goose-migrator-lambda/migrations/` in hometest-service following Goose naming conventions:

```sql
-- +goose Up
CREATE TABLE example (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid()
);

-- +goose Down
DROP TABLE example;
```

## Invocation

Invoke the Lambda manually to run pending migrations:

```bash
aws lambda invoke \
  --function-name <function-name> \
  --payload '{"action":"migrate"}' \
  response.json
```

Or use the helper script (handles CloudWatch log tailing):

```bash
./scripts/invoke-goose-migrator.sh <function-name> migrate <environment>
```

## Security

- **VPC Access**: Lambda runs within private subnets, no public internet access
- **Secrets Manager**: Master user password via `DB_SECRET_ARN`; app user password via `APP_USER_SECRET_NAME`
- **IAM**: Least-privilege execution role scoped to specific secret ARNs and KMS key
- **Schema isolation**: Each environment gets its own schema (`hometest_<env>`) with a dedicated `app_user_<schema>` role

## Related

- [hometest-service — goose-migrator-lambda](https://github.com/NHSDigital/hometest-service/tree/main/lambdas/goose-migrator-lambda) — source code, migrations, build and test scripts
- [aurora-postgres](../aurora-postgres/) — Aurora PostgreSQL cluster
- [lambda](../lambda/) — Application Lambda functions

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.14.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.37.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | ~> 3.6 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | ~> 6.37.0 |
| <a name="provider_random"></a> [random](#provider\_random) | ~> 3.6 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_goose_migrator_lambda"></a> [goose\_migrator\_lambda](#module\_goose\_migrator\_lambda) | ../../modules/lambda | n/a |

## Resources

| Name | Type |
| ---- | ---- |
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
| ---- | ----------- | ---- | ------- | :------: |
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
| <a name="input_goose_migrator_zip_path"></a> [goose\_migrator\_zip\_path](#input\_goose\_migrator\_zip\_path) | Path to the pre-built goose-migrator zip file | `string` | n/a | yes |
| <a name="input_grant_rds_iam"></a> [grant\_rds\_iam](#input\_grant\_rds\_iam) | Whether to GRANT rds\_iam to the app\_user so that app lambdas can use IAM token authentication. Independent of how the migrator itself connects. | `bool` | `false` | no |
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | ARN of the customer-managed KMS key for encrypting Secrets Manager secrets | `string` | n/a | yes |
| <a name="input_project_name"></a> [project\_name](#input\_project\_name) | Project name used for resource naming | `string` | n/a | yes |
| <a name="input_security_group_ids"></a> [security\_group\_ids](#input\_security\_group\_ids) | List of security group IDs for Lambda VPC config | `list(string)` | n/a | yes |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | List of subnet IDs for Lambda VPC config | `list(string)` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags for all resources | `map(string)` | `{}` | no |
| <a name="input_use_iam_auth"></a> [use\_iam\_auth](#input\_use\_iam\_auth) | Whether the goose migrator Lambda itself connects to Aurora using IAM auth instead of Secrets Manager password. The master user typically uses password auth, so this is usually false. | `bool` | `false` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_app_user_secret_arn"></a> [app\_user\_secret\_arn](#output\_app\_user\_secret\_arn) | ARN of the Secrets Manager secret containing app\_user credentials |
| <a name="output_app_user_secret_name"></a> [app\_user\_secret\_name](#output\_app\_user\_secret\_name) | Name of the Secrets Manager secret containing app\_user credentials |
| <a name="output_app_username"></a> [app\_username](#output\_app\_username) | The database username for the schema-scoped app\_user |
| <a name="output_function_arn"></a> [function\_arn](#output\_function\_arn) | ARN of the Lambda function |
| <a name="output_function_name"></a> [function\_name](#output\_function\_name) | Name of the Lambda function for invocation |
<!-- END_TF_DOCS -->
