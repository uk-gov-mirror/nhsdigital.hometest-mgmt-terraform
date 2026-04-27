# Creating a New Development Environment

This guide walks through the steps to create a new environment (e.g. `dev2`, `staging`, `test`) for the NHS HomeTest Service.

## TL;DR

```bash
# 1. Login to AWS CLI
aws sso login --profile PoC-Dev

# 2. Export AWS profile (or add to ~/.zshrc)
export AWS_PROFILE=PoC-Dev

# 3. Copy the template environment
ENV_NAME="dev2"  # Change to your environment name
cp -r infrastructure/environments/poc/hometest-app/dev-example \
      infrastructure/environments/poc/hometest-app/${ENV_NAME}

# 4. Update the environment name in env.hcl
sed -i '' "s/environment = \".*\"/environment = \"${ENV_NAME}\"/" \
  infrastructure/environments/poc/hometest-app/${ENV_NAME}/env.hcl

# 5. Deploy the database migrator
cd infrastructure/environments/poc/hometest-app/${ENV_NAME}/lambda-goose-migrator
terragrunt apply

# 6. Deploy the app
cd ../app
terragrunt apply
```

## Contents

- [Creating a New Development Environment](#creating-a-new-development-environment)
  - [TL;DR](#tldr)
  - [Contents](#contents)
  - [Overview](#overview)
  - [Prerequisites](#prerequisites)
  - [AWS SSO Setup](#aws-sso-setup)
    - [First-time configuration](#first-time-configuration)
    - [Login and export profile](#login-and-export-profile)
  - [Quick Start](#quick-start)
  - [Step-by-Step Guide](#step-by-step-guide)
    - [Step 1: Create the Environment Directory](#step-1-create-the-environment-directory)
    - [Step 2: Create `env.hcl`](#step-2-create-envhcl)
    - [Step 3: Create `app/terragrunt.hcl`](#step-3-create-appterragrunthcl)
    - [Step 4: Customise the Configuration (Optional)](#step-4-customise-the-configuration-optional)
      - [4a. Optional: Custom Domain](#4a-optional-custom-domain)
      - [4b. Optional: Add Environment-Specific Lambdas](#4b-optional-add-environment-specific-lambdas)
      - [4c. Optional: Enable WireMock](#4c-optional-enable-wiremock)
      - [4d. Optional: Use Placeholder Lambdas](#4d-optional-use-placeholder-lambdas)
    - [Step 5: Create the Database Migrator](#step-5-create-the-database-migrator)
    - [Step 6: Validate the Configuration](#step-6-validate-the-configuration)
    - [Step 7: Deploy](#step-7-deploy)
      - [Option A: Deploy Locally](#option-a-deploy-locally)
      - [Option B: Deploy via GitHub Actions](#option-b-deploy-via-github-actions)
  - [Quick Deploy (Iterative Development)](#quick-deploy-iterative-development)
    - [Deploy Only Lambdas](#deploy-only-lambdas)
    - [Deploy Only UI](#deploy-only-ui)
    - [Deploy Both (Skip Nothing, But Target Lambdas)](#deploy-both-skip-nothing-but-target-lambdas)
    - [Force Rebuild](#force-rebuild)
    - [Environment Variables Reference](#environment-variables-reference)
    - [Step 8: Verify the Deployment](#step-8-verify-the-deployment)
  - [File Structure After Creation](#file-structure-after-creation)
  - [How It Works](#how-it-works)
  - [Destroying an Environment](#destroying-an-environment)
  - [Checklist](#checklist)
  - [Troubleshooting](#troubleshooting)
    - ["Can't find env.hcl"](#cant-find-envhcl)
    - [DNS not resolving](#dns-not-resolving)
    - [Lambda build failures](#lambda-build-failures)
    - [SPA build failures](#spa-build-failures)
    - [`NoCredentialProviders` or authentication errors](#nocredentialproviders-or-authentication-errors)
    - [State lock errors](#state-lock-errors)

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
- AWS SSO access configured and logged in (see [AWS SSO Setup](#aws-sso-setup) below)
- Terraform 1.14.8 and Terragrunt 1.0.0 installed (run `mise install`)
- The `hometest-service` repo cloned alongside this repo (for Lambda and SPA source code)

```text
parent-dir/
├── hometest-mgmt-terraform/   (this repo)
└── hometest-service/           (application code)
    ├── lambdas/
    └── ui/
```

## AWS SSO Setup

### First-time configuration

If you haven't configured the AWS SSO profile yet, run the interactive wizard:

```bash
aws configure sso
```

When prompted, enter the following values:

| Prompt | Value |
|--------|-------|
| SSO session name | `nhs` |
| SSO start URL | `https://d-9c67018f89.awsapps.com/start/#` |
| SSO region | `eu-west-2` |
| SSO registration scopes | `sso:account:access` |

The wizard will open a browser for authentication. After authenticating, select the **PoC account** and **Hometest-NonProd-Developers** role. When asked for a profile name, enter `PoC-Dev`.

This creates the following in `~/.aws/config`:

```ini
[sso-session nhs]
sso_start_url = https://d-9c67018f89.awsapps.com/start/#
sso_region = eu-west-2
sso_registration_scopes = sso:account:access

[profile PoC-Dev]
sso_session = nhs
sso_account_id = 781863586270
sso_role_name = Hometest-NonProd-Developers
region = eu-west-2
```

### Login and export profile

Before running any `terragrunt` command, you must log in and export the profile:

```bash
aws sso login --profile PoC-Dev
export AWS_PROFILE=PoC-Dev
```

> **Important:** You must `export AWS_PROFILE` in every new terminal session. Without it, Terraform/Terragrunt will not pick up your SSO credentials and you'll get `NoCredentialProviders` errors.

Verify credentials are working:

```bash
aws sts get-caller-identity
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

### Step 5: Create the Database Migrator

Each environment requires its own Goose database migrator to set up the per-environment database schema. Create the subdirectory and config:

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

There are two ways to deploy an environment: **locally** or via **GitHub Actions**.

#### Option A: Deploy Locally

```bash
# Ensure AWS credentials are active
export AWS_PROFILE=PoC-Dev

cd infrastructure/environments/poc/hometest-app/${ENV_NAME}/app
terragrunt apply
```

When deploying locally, the build hooks reference your **local clone** of the `hometest-service` repo (expected at `../hometest-service/` relative to this repo's root). This means your local Lambda and SPA source code is what gets built and deployed — useful for testing changes before they're merged.

> **Don't forget the database migrator!** After deploying the app, you must also deploy the goose migrator to set up the database schema for your environment:
>
> ```bash
> cd infrastructure/environments/poc/hometest-app/${ENV_NAME}/lambda-goose-migrator
> terragrunt apply
> ```

#### Option B: Deploy via GitHub Actions

You can also trigger a deployment from the GitHub Actions UI:

**[Deploy HomeTest App](https://github.com/NHSDigital/hometest-mgmt-terraform/actions/workflows/deploy-hometest-app.yaml)** (workflow file: `.github/workflows/deploy-hometest-app.yaml`)

Click **"Run workflow"** and configure the following inputs:

| Input | Type | Default | Description |
|-------|------|---------|-------------|
| `hometest_service_ref` | string | `main` | Branch, tag, or SHA to checkout for `hometest-service`. Unlike local deployment which uses your local copy, the pipeline checks out the specified ref from the remote repo. |
| `account` | choice | `poc` | AWS account to deploy to (`poc` or `dev`). |
| `env` | choice | `dev` | Target environment (e.g. `dev`, `uat`, `demo`, `staging`). |
| `action` | choice | `plan` | Terraform action: `plan` (preview), `apply` (deploy), or `destroy` (teardown). |
| `targets` | string | _(empty)_ | Comma-separated list of resources to target in the app stack only (e.g. `module.lambdas["order-status-lambda"]`). Leave empty for full deployment. Does not apply to the migrator. |
| `skip_migrator` | boolean | `false` | Skip the goose migrator deployment entirely (deploy app stack only). Equivalent to `SKIP_MIGRATOR=true` locally. |

> **Important:** The `env` input is a fixed choice list. To deploy a new environment from the pipeline, you must first add it to the `options` list under `inputs.env` in `.github/workflows/deploy-hometest-app.yaml`:
>
> ```yaml
> env:
>   description: "Target environment to deploy"
>   required: true
>   type: choice
>   default: dev
>   options:
>     - dev
>     - uat
>     - demo
>     - staging
>     - dev2  # ← add your new environment here
> ```
>
> **Tip:** For a first deployment of a new environment, use `action: plan` first to review the changes, then re-run with `action: apply`.

Both local and pipeline deployments will:

1. Build Lambda functions from `hometest-service/lambdas/` (via `build_lambdas` before hook — skipped if source unchanged)
2. Build the Next.js SPA from `hometest-service/ui/` (via `build_spa` before hook — skipped if source unchanged)
3. Create all AWS resources (Lambda, API Gateway, CloudFront, S3, SQS, Route53)
4. Upload the SPA to S3 and invalidate CloudFront cache (via `upload_spa` after hook)

> **Note:** Build hooks use content hashing to skip rebuilds when source code hasn't changed. To force a rebuild, set `FORCE_LAMBDA_REBUILD=true` or `FORCE_SPA_REBUILD=true`.

## Quick Deploy (Iterative Development)

Once your environment is fully deployed, you can rapidly redeploy just lambdas, just the UI, or both without running a full `terragrunt apply`. This is useful when iterating on `hometest-service` code.

| What changed | Command | How it works |
|--------------|---------|--------------|
| Lambda code only | `SKIP_SPA=true terragrunt apply -target='module.lambdas["<name>"].aws_lambda_function.this' -auto-approve` | Skips SPA build/upload, targets only the lambda resource → Terraform re-uploads the zip |
| UI code only | `SKIP_LAMBDAS=true terragrunt apply -refresh-only -auto-approve` | Skips lambda build, Terraform is a no-op, but the `upload_spa` after-hook still runs → S3 sync + CloudFront invalidation |
| Both | `terragrunt apply -target='module.lambdas["<name>"].aws_lambda_function.this' -auto-approve` | Builds both, targets lambda for Terraform, SPA hooks run regardless of `-target` |

All commands below assume you are in the environment's `app/` directory:

```bash
export AWS_PROFILE=PoC-Dev
cd infrastructure/environments/poc/hometest-app/${ENV_NAME}/app
```

### Deploy Only Lambdas

Skip the SPA build/upload and target only the lambda resources that changed:

```bash
# All (and only) lambdas
SKIP_SPA=true terragrunt apply -target='module.lambdas' -auto-approve

## Or use the mise shortcut:
mise run deploy-lambdas

# Single lambda (~30s build + ~20s targeted apply)
SKIP_SPA=true terragrunt apply \
  -target='module.lambdas["login-lambda"].aws_lambda_function.this' \
  -auto-approve

# Multiple lambdas
SKIP_SPA=true terragrunt apply \
  -target='module.lambdas["login-lambda"].aws_lambda_function.this' \
  -target='module.lambdas["order-service-lambda"].aws_lambda_function.this' \
  -auto-approve
```

**Available lambda target names** (from `_envcommon/hometest-app.hcl`):

| Lambda | Target |
|--------|--------|
| Eligibility Lookup | `module.lambdas["eligibility-lookup-lambda"].aws_lambda_function.this` |
| Order Router | `module.lambdas["order-router-lambda"].aws_lambda_function.this` |
| Login | `module.lambdas["login-lambda"].aws_lambda_function.this` |
| Session | `module.lambdas["session-lambda"].aws_lambda_function.this` |
| Order Result | `module.lambdas["order-result-lambda"].aws_lambda_function.this` |
| Order Service | `module.lambdas["order-service-lambda"].aws_lambda_function.this` |
| Get Order | `module.lambdas["get-order-lambda"].aws_lambda_function.this` |
| Get Results | `module.lambdas["get-results-lambda"].aws_lambda_function.this` |
| Order Status | `module.lambdas["order-status-lambda"].aws_lambda_function.this` |
| Postcode Lookup | `module.lambdas["postcode-lookup-lambda"].aws_lambda_function.this` |

### Deploy Only UI

Skip the lambda build. Use `-target=provider.aws` so Terraform is a no-op, but the `upload_spa` after-hook still runs (builds the SPA, syncs to S3, invalidates CloudFront):

```bash
SKIP_LAMBDAS=true terragrunt apply -target=provider.aws -auto-approve

# Or use the mise shortcut:
mise run deploy-ui
```

### Deploy Both (Skip Nothing, But Target Lambdas)

If you changed both lambda and UI code but want to skip evaluating the full Terraform graph:

```bash
terragrunt apply -target='module.lambdas' -auto-approve

# Or use the mise shortcut:
mise run deploy-all
```

The SPA build + upload hooks run regardless of `-target` (they are before/after hooks, not Terraform resources).

### Force Rebuild

Override the content-hash build cache:

```bash
# Force rebuild lambdas only
FORCE_LAMBDA_REBUILD=true SKIP_SPA=true terragrunt apply \
  -target='module.lambdas["login-lambda"].aws_lambda_function.this' \
  -auto-approve

# Force rebuild everything
FORCE_LAMBDA_REBUILD=true FORCE_SPA_REBUILD=true terragrunt apply
```

### Environment Variables Reference

| Variable | Effect |
|----------|--------|
| `SKIP_SPA=true` | Skip SPA build (before-hook) and upload (after-hook) |
| `SKIP_LAMBDAS=true` | Skip lambda build (before-hook) |
| `FORCE_LAMBDA_REBUILD=true` | Ignore lambda build cache — always rebuild |
| `FORCE_SPA_REBUILD=true` | Ignore SPA build cache — always rebuild |

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
- [ ] Created `lambda-goose-migrator/terragrunt.hcl` for DB migrations
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
pnpm install
pnpm run build
```

To force a rebuild: `FORCE_LAMBDA_REBUILD=true terragrunt apply`

### SPA build failures

```bash
cd ../hometest-service/ui
pnpm install
pnpm run build
```

To force a rebuild: `FORCE_SPA_REBUILD=true terragrunt apply`

### `NoCredentialProviders` or authentication errors

Ensure you have exported the correct AWS profile:

```bash
aws sso login --profile PoC-Dev
export AWS_PROFILE=PoC-Dev
```

Verify credentials are working:

```bash
aws sts get-caller-identity
```

### State lock errors

Another deployment may be in progress. Check for stale locks:

```bash
terragrunt force-unlock <LOCK_ID>
```
