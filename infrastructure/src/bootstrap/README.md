# Bootstrap Module for Terraform/Terragrunt with GitHub Actions

This bootstrap module creates the foundational infrastructure required to run Terraform/Terragrunt from GitHub Actions using OIDC authentication.

## Features

- **S3 Backend** - Versioned, encrypted bucket for Terraform state storage
- **DynamoDB Locking** - State locking to prevent concurrent modifications
- **KMS Encryption** - Customer-managed encryption keys for state at rest
- **GitHub OIDC** - Secure, keyless authentication from GitHub Actions
- **Access Logging** - Optional audit trail for state bucket access
- **Security Best Practices** - TLS enforcement, public access blocking, permissions boundaries

## Security Features

| Feature | Description |
|---------|-------------|
| **OIDC Authentication** | No long-lived AWS credentials stored in GitHub |
| **Branch/Environment Restrictions** | Only specified branches and environments can assume the role |
| **KMS Encryption** | State files encrypted with customer-managed key |
| **Key Rotation** | Automatic annual KMS key rotation enabled |
| **TLS 1.2 Enforcement** | S3 bucket requires TLS 1.2 minimum |
| **Public Access Blocked** | All public access settings blocked on buckets |
| **Deletion Protection** | DynamoDB and S3 have lifecycle protection |
| **Least Privilege IAM** | Scoped permissions for state management |
| **Permissions Boundary** | Optional boundary to prevent privilege escalation |
| **Session Duration** | 1-hour maximum session for GitHub Actions role |

## Prerequisites

1. AWS CLI configured with appropriate permissions
2. Terraform >= 1.5.0
3. AWS account with permissions to create IAM, S3, DynamoDB, and KMS resources

## Usage

### Initial Bootstrap (First Time)

1. Copy the example variables file:

   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

2. Edit `terraform.tfvars` with your values:

   ```hcl
   project_name = "hometest"
   environment  = "mgmt"
   account_name = "hometest-mgmt"
   github_repo  = "your-org/hometest-mgmt-terraform"
   ```

3. Initialize and apply:

   ```bash
   terraform init
   terraform plan -out=tfplan
   terraform apply tfplan
   ```

4. Note the outputs for GitHub configuration:

   ```bash
   terraform output gha_oidc_role_arn
   terraform output backend_config_hcl
   ```

5. Add the role ARN to GitHub repository secrets as `AWS_ROLE_ARN`

### Migrating State to S3 Backend

After the initial apply with local state:

1. Uncomment the backend configuration in `providers.tf`
2. Run `terraform init -migrate-state`
3. Confirm the state migration

## GitHub Actions Configuration

Add the following to your workflow:

```yaml
jobs:
  terraform:
    runs-on: ubuntu-latest
    permissions:
      id-token: write   # Required for OIDC
      contents: read

    steps:
      - uses: actions/checkout@v4

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v6
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
          aws-region: eu-west-2

      - name: Terraform Init
        run: terraform init

      - name: Terraform Plan
        run: terraform plan
```

## Terragrunt Configuration

Create a `terragrunt.hcl` in your root:

```hcl
remote_state {
  backend = "s3"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  config = {
    bucket         = "hometest-mgmt-tfstate-ACCOUNT_ID"
    key            = "${path_relative_to_include()}/terraform.tfstate"
    region         = "eu-west-2"
    encrypt        = true
    dynamodb_table = "hometest-mgmt-tfstate-lock"
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `aws_region` | AWS region for resources | `string` | `"eu-west-2"` | no |
| `project_name` | Project name for resource naming | `string` | n/a | yes |
| `environment` | Environment (mgmt, dev, staging, prod) | `string` | `"mgmt"` | no |
| `account_name` | AWS account name/alias | `string` | n/a | yes |
| `github_repo` | GitHub repository (owner/repo) | `string` | n/a | yes |
| `github_branches` | Allowed branches for OIDC | `list(string)` | `["main", "develop"]` | no |
| `github_environments` | Allowed environments for OIDC | `list(string)` | `["dev", "staging", "prod"]` | no |
| `enable_state_bucket_logging` | Enable S3 access logging | `bool` | `true` | no |
| `state_bucket_retention_days` | Days to retain old state versions | `number` | `90` | no |
| `enable_dynamodb_point_in_time_recovery` | Enable DynamoDB PITR | `bool` | `true` | no |
| `kms_key_deletion_window_days` | KMS key deletion window | `number` | `30` | no |
| `additional_iam_policy_arns` | Additional policies for GHA role | `list(string)` | `[]` | no |
| `tags` | Additional tags for resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| `state_bucket_name` | S3 bucket name for Terraform state |
| `state_bucket_arn` | S3 bucket ARN |
| `dynamodb_table_name` | DynamoDB table name for state locking |
| `dynamodb_table_arn` | DynamoDB table ARN |
| `kms_key_arn` | KMS key ARN for encryption |
| `kms_key_alias` | KMS key alias |
| `github_oidc_provider_arn` | GitHub OIDC provider ARN |
| `gha_oidc_role_arn` | GitHub Actions role ARN (for GitHub secrets) |
| `gha_oidc_role_name` | GitHub Actions role name |
| `logging_bucket_name` | S3 logging bucket name |
| `backend_config` | Backend configuration object |
| `backend_config_hcl` | Backend configuration in HCL format |

## Extending Permissions

The default IAM policy provides read-only access for Terraform planning. To add write permissions:

1. Edit the `infrastructure_policy` in `iam.tf`
2. Uncomment or add statements for your specific resources
3. Follow least-privilege principles - only grant what's needed

Example for EC2 write access:

```hcl
statement {
  sid    = "EC2WriteAccess"
  effect = "Allow"
  actions = [
    "ec2:RunInstances",
    "ec2:TerminateInstances",
    "ec2:CreateTags"
  ]
  resources = ["*"]
  condition {
    test     = "StringEquals"
    variable = "aws:RequestedRegion"
    values   = ["eu-west-2"]
  }
}
```

## Troubleshooting

### OIDC Authentication Fails

1. Verify the GitHub repo name matches exactly
2. Check branch/environment restrictions
3. Ensure workflow has `id-token: write` permission

### State Lock Issues

1. Check DynamoDB table exists and is accessible
2. Verify KMS key permissions
3. Use `terraform force-unlock <LOCK_ID>` if needed

### Encryption Errors

1. Verify KMS key policy includes the GitHub Actions role
2. Check bucket policy allows encryption operations

## Cost Considerations

- **S3**: ~$0.023/GB/month for storage + request costs
- **DynamoDB**: Pay-per-request, typically < $1/month
- **KMS**: $1/month per CMK + $0.03 per 10,000 requests
- **Total**: Usually < $5/month for typical usage

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

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_account_region.disabled](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/account_region) | resource |
| [aws_iam_openid_connect_provider.github](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_openid_connect_provider) | resource |
| [aws_iam_policy.deny_regions](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_policy.gha_permissions_boundary](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_role.gha_oidc_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.gha_infrastructure](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.gha_tfstate](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy_attachment.additional_policies](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.gha_deny_regions](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_kms_alias.logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_alias.tfstate](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_key.logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_kms_key.tfstate](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_resourcegroups_group.all](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/resourcegroups_group) | resource |
| [aws_resourcegroups_group.bootstrap](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/resourcegroups_group) | resource |
| [aws_s3_bucket.tfstate](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket.tfstate_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_lifecycle_configuration.tfstate](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_lifecycle_configuration) | resource |
| [aws_s3_bucket_lifecycle_configuration.tfstate_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_lifecycle_configuration) | resource |
| [aws_s3_bucket_logging.tfstate](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_logging) | resource |
| [aws_s3_bucket_policy.tfstate](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_s3_bucket_public_access_block.tfstate](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_public_access_block.tfstate_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.tfstate](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.tfstate_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_versioning.tfstate](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning) | resource |
| [aws_s3_bucket_versioning.tfstate_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning) | resource |
| [aws_iam_policy_document.infrastructure_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.tfstate_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_additional_iam_policy_arns"></a> [additional\_iam\_policy\_arns](#input\_additional\_iam\_policy\_arns) | List of additional IAM policy ARNs to attach to the GitHub Actions role | `list(string)` | `[]` | no |
| <a name="input_aws_account_id"></a> [aws\_account\_id](#input\_aws\_account\_id) | AWS account ID for resources | `string` | n/a | yes |
| <a name="input_aws_account_shortname"></a> [aws\_account\_shortname](#input\_aws\_account\_shortname) | AWS account short name/alias for resource naming | `string` | n/a | yes |
| <a name="input_aws_allowed_regions"></a> [aws\_allowed\_regions](#input\_aws\_allowed\_regions) | List of AWS regions allowed for resource deployment | `list(string)` | <pre>[<br/>  "eu-west-2",<br/>  "us-east-1"<br/>]</pre> | no |
| <a name="input_aws_region"></a> [aws\_region](#input\_aws\_region) | AWS region for resources | `string` | n/a | yes |
| <a name="input_enable_state_bucket_logging"></a> [enable\_state\_bucket\_logging](#input\_enable\_state\_bucket\_logging) | Enable access logging for the state bucket | `bool` | `true` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment name (e.g., mgmt, dev, staging, prod) | `string` | `"mgmt"` | no |
| <a name="input_github_allow_all_branches"></a> [github\_allow\_all\_branches](#input\_github\_allow\_all\_branches) | Allow all branches to assume the OIDC role (disables branch restrictions). Use with caution in production. | `bool` | `false` | no |
| <a name="input_github_branches"></a> [github\_branches](#input\_github\_branches) | List of GitHub branch patterns allowed to assume the OIDC role | `list(string)` | <pre>[<br/>  "main",<br/>  "develop"<br/>]</pre> | no |
| <a name="input_github_environments"></a> [github\_environments](#input\_github\_environments) | List of GitHub environments allowed to assume the OIDC role | `list(string)` | <pre>[<br/>  "dev",<br/>  "staging",<br/>  "prod"<br/>]</pre> | no |
| <a name="input_github_repo"></a> [github\_repo](#input\_github\_repo) | GitHub repository in format 'owner/repo-name' | `string` | n/a | yes |
| <a name="input_kms_key_deletion_window_days"></a> [kms\_key\_deletion\_window\_days](#input\_kms\_key\_deletion\_window\_days) | Number of days before KMS key is deleted | `number` | `30` | no |
| <a name="input_project_name"></a> [project\_name](#input\_project\_name) | Project name used for resource naming | `string` | n/a | yes |
| <a name="input_state_bucket_retention_days"></a> [state\_bucket\_retention\_days](#input\_state\_bucket\_retention\_days) | Number of days to retain noncurrent versions of state files | `number` | `90` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags for all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_allowed_regions"></a> [allowed\_regions](#output\_allowed\_regions) | List of AWS regions that are allowed |
| <a name="output_backend_config_hcl"></a> [backend\_config\_hcl](#output\_backend\_config\_hcl) | Terraform backend configuration in HCL format |
| <a name="output_denied_regions"></a> [denied\_regions](#output\_denied\_regions) | List of all AWS regions denied via IAM policy |
| <a name="output_deny_regions_policy_arn"></a> [deny\_regions\_policy\_arn](#output\_deny\_regions\_policy\_arn) | ARN of the IAM policy that denies non-allowed regions |
| <a name="output_disabled_opt_in_regions"></a> [disabled\_opt\_in\_regions](#output\_disabled\_opt\_in\_regions) | List of opt-in AWS regions that have been disabled |
| <a name="output_gha_oidc_role_arn"></a> [gha\_oidc\_role\_arn](#output\_gha\_oidc\_role\_arn) | ARN of the GitHub Actions OIDC role (store as AWS\_ROLE\_ARN in GitHub secrets) |
| <a name="output_gha_oidc_role_name"></a> [gha\_oidc\_role\_name](#output\_gha\_oidc\_role\_name) | Name of the GitHub Actions OIDC role |
| <a name="output_github_oidc_provider_arn"></a> [github\_oidc\_provider\_arn](#output\_github\_oidc\_provider\_arn) | ARN of the GitHub OIDC provider |
| <a name="output_kms_key_alias"></a> [kms\_key\_alias](#output\_kms\_key\_alias) | Alias of the KMS key for state encryption |
| <a name="output_kms_key_arn"></a> [kms\_key\_arn](#output\_kms\_key\_arn) | ARN of the KMS key for state encryption |
| <a name="output_logging_bucket_name"></a> [logging\_bucket\_name](#output\_logging\_bucket\_name) | Name of the S3 bucket for access logs |
| <a name="output_logs_kms_key_arn"></a> [logs\_kms\_key\_arn](#output\_logs\_kms\_key\_arn) | ARN of the KMS key for logs encryption |
| <a name="output_logs_kms_key_id"></a> [logs\_kms\_key\_id](#output\_logs\_kms\_key\_id) | ID of the KMS key for logs encryption |
| <a name="output_state_bucket_arn"></a> [state\_bucket\_arn](#output\_state\_bucket\_arn) | ARN of the S3 bucket for Terraform state |
| <a name="output_state_bucket_name"></a> [state\_bucket\_name](#output\_state\_bucket\_name) | Name of the S3 bucket for Terraform state |
<!-- END_TF_DOCS -->
