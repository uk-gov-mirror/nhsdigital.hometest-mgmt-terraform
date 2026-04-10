# Creating a New Development Environment

This guide walks through the steps to create a new environment (e.g. `dev2`, `staging`, `test`) for the NHS HomeTest Service.

## Overview

Each environment deploys its own isolated set of:

- Lambda functions (eligibility-lookup, order-router, login, session, order-result, order-service, get-order, get-results, order-status, postcode-lookup)
- API Gateway (REST API with per-lambda path routing)
- CloudFront distribution + S3 bucket (Next.js SPA)
- SQS queues (for async order processing)
- Route53 DNS record (default: `{env}.poc.hometest.service.nhs.uk`, or custom via `env.hcl` overrides)

All environments share core infrastructure (VPC, WAF, ACM, KMS, Cognito, Aurora PostgreSQL, ECS) deployed under `poc/core/`.

## Prerequisites

- Core infrastructure already deployed (`network`, `shared_services`, `aurora-postgres`, `lambda-goose-migrator`, and optionally `ecs` for WireMock)
- AWS SSO access configured (`aws sso login --profile Admin-PoC`)
- Terraform 1.14.8 and Terragrunt 1.0.0 installed (run `mise install`)
- The `hometest-service` repo cloned alongside this repo (for Lambda and SPA source code)

```text
parent-dir/
├── hometest-mgmt-terraform/   (this repo)
└── hometest-service/           (application code)
    ├── lambdas/
    └── ui/
```

## Quick Start

The easiest way to create a new environment is to copy the `dev-example` template:

```bash
ENV_NAME="dev2"  # Change this to your desired environment name
cp -r infrastructure/environments/poc/hometest-app/dev-example \
      infrastructure/environments/poc/hometest-app/${ENV_NAME}
```

Then update `env.hcl` with the correct environment name and follow the customisation steps below.

## Step-by-Step Guide

### Step 1: Create the Environment Directory

Create a new directory under `infrastructure/environments/poc/hometest-app/` with your environment name:

```bash
ENV_NAME="dev2"  # Change this to your desired environment name
mkdir -p infrastructure/environments/poc/hometest-app/${ENV_NAME}/app
```

### Step 2: Create `env.hcl`

Create `infrastructure/environments/poc/hometest-app/${ENV_NAME}/env.hcl`:

```hcl
# Set common variables for the environment. This is automatically pulled in in the root terragrunt.hcl configuration to
# feed forward to the child modules.
locals {
  environment = "dev2"  # Must match the directory name
}
```

> **Note:** The environment name is also auto-derived from the parent directory name via `basename(dirname(get_terragrunt_dir()))` in `_envcommon/hometest-app.hcl`. The `env.hcl` value should match the directory name for consistency.

The `environment` value is used for:

- Terraform state key: `nhs-hometest-poc-{environment}-app.tfstate` (pattern: `{account_name}-{environment}-{basename}.tfstate`)
- Resource naming: `nhs-hometest-{environment}-*`
- Default DNS: `{environment}.poc.hometest.service.nhs.uk` (customisable via domain overrides in `env.hcl`)
- Database schema: `hometest_{environment}` (schema-per-environment in shared Aurora DB)
- Resource tagging: `Environment = "{environment}"`

### Step 3: Create `app/terragrunt.hcl`

Create `infrastructure/environments/poc/hometest-app/${ENV_NAME}/app/terragrunt.hcl`.

Copy from the `dev-example` environment as a starting point:

```bash
cp infrastructure/environments/poc/hometest-app/dev-example/app/terragrunt.hcl \
   infrastructure/environments/poc/hometest-app/${ENV_NAME}/app/terragrunt.hcl
```

The minimal `app/terragrunt.hcl` just includes the root and shared app config:

```hcl
# TERRAGRUNT CONFIGURATION FOR dev2 ENVIRONMENT
# Deployment with: cd poc/hometest-app/dev2/app && terragrunt apply
#
# All shared configuration (dependencies, lambda definitions, hooks) comes from _envcommon/hometest-app.hcl.
# Environment name ("dev2") is derived from the parent directory name.

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "app" {
  path           = find_in_parent_folders("_envcommon/hometest-app.hcl")
  expose         = true
  merge_strategy = "deep"
}

# Uses all defaults from _envcommon/hometest-app.hcl — no overrides needed.
# To add environment-specific overrides, uncomment and extend:
# inputs = {
#   lambdas = {
#     "my-custom-lambda" = { ... }
#   }
# }
```

### Step 4: Customise the Configuration (Optional)

The new `app/terragrunt.hcl` inherits all settings from `_envcommon/hometest-app.hcl` automatically, including all Lambda definitions, build hooks, API Gateway config, CloudFront, and SQS. Most dev environments need **no overrides at all**.

#### 4a. Optional: Custom Domain

By default, the environment gets URLs derived from the POC wildcard cert:

| Service | URL pattern | Example (`dev2`) |
|---------|-------------|-------------------|
| SPA (UI) | `{env}.poc.hometest.service.nhs.uk` | `dev2.poc.hometest.service.nhs.uk` |
| API | `api-{env}.poc.hometest.service.nhs.uk` | `api-dev2.poc.hometest.service.nhs.uk` |

These defaults require no extra configuration — they are covered by the shared wildcard certificate (`*.poc.hometest.service.nhs.uk`) from `shared_services`.

To use a custom domain outside the POC wildcard scope (e.g. `dev2.hometest.service.nhs.uk`), add domain overrides directly in `env.hcl`:

```hcl
locals {
  environment = "dev2"

  # Domain overrides — custom domains outside the POC wildcard cert scope.
  # Dedicated per-env certificates are created by the hometest-app module.
  env_domain = "dev2.hometest.service.nhs.uk"
  api_domain = "api.dev2.hometest.service.nhs.uk"

  create_cloudfront_certificate = true
  create_api_certificate        = true
}
```

> **Note:** Without domain overrides, the shared wildcard certificate from `shared_services` is used. Custom domains require `create_cloudfront_certificate = true` and `create_api_certificate = true` so the module creates per-environment certificates.

#### 4b. Optional: Add Environment-Specific Lambdas

To add extra Lambdas (e.g. a health check) beyond the shared set, add an `inputs` block in your `app/terragrunt.hcl`:

```hcl
inputs = {
  lambdas = {
    "hello-world-lambda" = {
      description     = "Hello World Lambda - Health Check"
      api_path_prefix = "hello-world"
      handler         = "index.handler"
      timeout         = 30
      memory_size     = 256
      environment = {
        NODE_OPTIONS = "--enable-source-maps"
        ENVIRONMENT  = basename(get_terragrunt_dir())
      }
    }
  }
}
```

These are **deep-merged** with the shared Lambda definitions from `_envcommon/hometest-app.hcl`.

#### 4c. Optional: Enable WireMock

To enable WireMock (ECS Fargate) for stubbing third-party APIs in E2E tests, add flags to `env.hcl`:

```hcl
locals {
  environment                = "dev2"
  enable_wiremock            = true
  wiremock_bypass_waf        = false   # Use shared ALB — WAF allowlist rule exempts WireMock traffic
  wiremock_scheduled_scaling = false   # Scale to 0 outside business hours (Mon-Fri 9AM-6PM UTC)
  # wiremock_use_spot        = false   # Use on-demand for stability (default: true for Spot)
  # wiremock_cpu             = 512     # 0.5 vCPU (default: 256)
  # wiremock_memory          = 1024    # 1 GiB (default: 512)
}
```

> **Prerequisite:** The `poc/core/ecs/` stack must be deployed for WireMock to work.

When WireMock is enabled, the SPA build automatically uses the WireMock endpoint (`wiremock-{env}.poc.hometest.service.nhs.uk`) as the NHS Login stub and sets `NEXT_PUBLIC_USE_WIREMOCK_AUTH=true`.

#### 4d. Optional: Use Placeholder Lambdas

To deploy infrastructure without real Lambda code (useful for testing infrastructure changes), add to your `app/terragrunt.hcl`:

```hcl
inputs = {
  use_placeholder_lambda = true
}
```

### Step 5: Create the Database Migrator (Optional)

Each environment can have its own Goose database migrator. Create the subdirectory and config:

```bash
mkdir -p infrastructure/environments/poc/hometest-app/${ENV_NAME}/lambda-goose-migrator
```

Create `lambda-goose-migrator/terragrunt.hcl`:

```hcl
include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "goose-migrator" {
  path           = find_in_parent_folders("_envcommon/goose-migrator.hcl")
  expose         = true
  merge_strategy = "deep"
}
```

### Step 6: Validate the Configuration

```bash
cd infrastructure/environments/poc/hometest-app/${ENV_NAME}/app

# Validate the Terragrunt config
terragrunt validate

# Preview what will be created
terragrunt plan
```

### Step 7: Deploy

```bash
cd infrastructure/environments/poc/hometest-app/${ENV_NAME}/app
terragrunt apply
```

This will:

1. Build Lambda functions from `hometest-service/lambdas/` (via `build_lambdas` before hook — skipped if source unchanged)
2. Build the Next.js SPA from `hometest-service/ui/` (via `build_spa` before hook — skipped if source unchanged)
3. Create all AWS resources (Lambda, API Gateway, CloudFront, S3, SQS, Route53)
4. Upload the SPA to S3 and invalidate CloudFront cache (via `upload_spa` after hook)

> **Note:** Build hooks use content hashing to skip rebuilds when source code hasn't changed. To force a rebuild, set `FORCE_LAMBDA_REBUILD=true` or `FORCE_SPA_REBUILD=true`.

### Step 8: Verify the Deployment

After successful apply, Terraform outputs will show:

```bash
# Check the outputs
terragrunt output

# Key outputs:
# spa_url              = "https://dev2.poc.hometest.service.nhs.uk"
# cloudfront_id        = "E1234567890ABC"
# lambda_function_names = ["nhs-hometest-dev2-eligibility-lookup-lambda", ...]
```

Test the deployment:

```bash
# SPA
curl -I https://dev2.poc.hometest.service.nhs.uk/
```

## File Structure After Creation

```text
infrastructure/environments/
├── _envcommon/                          # Shared configuration
│   ├── all.hcl                         # Global vars (region, project name)
│   ├── hometest-app.hcl               # Shared app config (lambdas, hooks, deps)
│   └── goose-migrator.hcl             # Shared DB migrator config
├── root.hcl                            # S3 backend, tags, AWS account check
└── poc/
    ├── account.hcl                      # AWS account ID and names
    ├── core/                            # Shared (already deployed)
    │   ├── env.hcl
    │   ├── bootstrap/
    │   ├── network/
    │   ├── shared_services/
    │   ├── aurora-postgres/
    │   ├── ecs/
    │   └── lambda-goose-migrator/
    └── hometest-app/
        ├── app.hcl                      # Account-level overrides (secrets, NHS Login)
        ├── dev/
        │   ├── env.hcl                  # Environment name + domain overrides
        │   ├── app/
        │   │   └── terragrunt.hcl       # App deployment config
        │   └── lambda-goose-migrator/
        │       └── terragrunt.hcl
        ├── dev-example/                 # ← Template for new environments
        │   ├── env.hcl
        │   ├── app/
        │   │   └── terragrunt.hcl
        │   └── lambda-goose-migrator/
        │       └── terragrunt.hcl
        ├── uat/
        ├── demo/
        ├── prod/
        └── dev2/                        # ← New environment
            ├── env.hcl                  # Environment name + optional domain/wiremock overrides
            ├── app/
            │   └── terragrunt.hcl       # App deployment config
            └── lambda-goose-migrator/
                └── terragrunt.hcl
```

## How It Works

The Terragrunt configuration chain:

1. **`env.hcl`** — Sets `environment = "dev2"`, plus optional domain overrides and feature flags (WireMock)
2. **`app/terragrunt.hcl`** includes:
   - `root.hcl` — S3 backend config, AWS account validation, tags
   - `_envcommon/hometest-app.hcl` — Shared defaults, Lambda definitions, build hooks, source paths, dependencies
3. **`hometest-app/app.hcl`** — Account-level overrides (secret names, NHS Login config), loaded by `_envcommon/hometest-app.hcl`
4. **Dependencies** (`network`, `shared_services`, `aurora-postgres`, `ecs`) — Read outputs from core via `dependency` blocks with mock outputs for plan/validate
5. **`inputs`** — Environment-specific values are deep-merged with the shared defaults

The state file will be stored at:

```text
s3://nhs-hometest-poc-core-s3-tfstate/nhs-hometest-poc-dev2-app.tfstate
```

> The key is `${account_name}-${environment}-${basename(path_relative_to_include())}.tfstate` (see `root.hcl`). The basename is `app` (the directory containing `terragrunt.hcl`), and environment comes from `env.hcl`.

## Destroying an Environment

To tear down an environment completely:

```bash
cd infrastructure/environments/poc/hometest-app/${ENV_NAME}/app
terragrunt destroy
```

The `empty_spa_bucket_on_destroy` hook will automatically clean all versioned objects from the S3 SPA bucket before Terraform attempts to delete it.

## Checklist

- [ ] Created `infrastructure/environments/poc/hometest-app/{env}/env.hcl`
- [ ] Created `infrastructure/environments/poc/hometest-app/{env}/app/terragrunt.hcl`
- [ ] (Optional) Added domain overrides in `env.hcl` for custom domain
- [ ] (Optional) Created `lambda-goose-migrator/terragrunt.hcl` for DB migrations
- [ ] (Optional) Enabled WireMock flags in `env.hcl`
- [ ] Ran `terragrunt validate` successfully
- [ ] Ran `terragrunt plan` and reviewed changes
- [ ] Ran `terragrunt apply` successfully
- [ ] Verified SPA loads at the environment URL
- [ ] Verified API responds via CloudFront routing

## Troubleshooting

### "Can't find env.hcl"

Ensure `env.hcl` exists in the environment directory (parent of `app/`):

```text
poc/hometest-app/{env}/env.hcl         ← correct
poc/hometest-app/{env}/app/env.hcl     ← wrong
```

### DNS not resolving

- **Default domains** (`{env}.poc.hometest.service.nhs.uk`) use the shared wildcard ACM certificate from `shared_services` — no extra setup needed.
- **Custom domains** (via domain overrides in `env.hcl`) require `create_cloudfront_certificate = true` and `create_api_certificate = true`. CloudFront creates a Route53 alias record automatically. Allow a few minutes for DNS propagation and certificate validation.

### Lambda build failures

Ensure the `hometest-service` repo is cloned alongside this repo and builds work:

```bash
cd ../hometest-service/lambdas
npm ci
npm run build
```

To force a rebuild: `FORCE_LAMBDA_REBUILD=true terragrunt apply`

### SPA build failures

```bash
cd ../hometest-service/ui
npm ci
npm run build
```

To force a rebuild: `FORCE_SPA_REBUILD=true terragrunt apply`

### State lock errors

Another deployment may be in progress. Check for stale locks:

```bash
terragrunt force-unlock <LOCK_ID>
```
