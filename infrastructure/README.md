# NHS HomeTest Infrastructure

This repository contains Terraform infrastructure code with Terragrunt for managing multi-account, multi-environment deployments of the NHS HomeTest Service.

## Architecture Overview

```text
┌─────────────────────────────────────────────────────────────────────────────────┐
│                           BOOTSTRAP (deployed manually once per account)         │
│  bootstrap/                                                                      │
│  ├─ S3 Backend (terraform state)      ├─ GitHub OIDC IAM Role                   │
│  ├─ KMS Key (state encryption)        ├─ Permissions Boundary                   │
│  └─ Access Logging S3 Bucket          └─ Region Opt-in Controls                 │
└─────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────┐
│                           CORE INFRASTRUCTURE                                    │
│  (Deployed once per account, shared across all environments)                    │
├─────────────────────────────────────────────────────────────────────────────────┤
│  network/                │  shared_services/                                    │
│  ├─ VPC                  │  ├─ KMS Keys (main + pii_data)                       │
│  ├─ Subnets (pub/priv/   │  ├─ WAF Regional (API Gateway / ALB)                │
│  │  firewall/data)       │  ├─ WAF CloudFront (SPAs)                            │
│  ├─ Security Groups      │  ├─ ACM Certificates (wildcard)                      │
│  │  (Lambda, Lambda-RDS, │  ├─ Cognito User Pool + Identity Pool                │
│  │   VPC Endpoints)      │  ├─ Developer IAM Role                               │
│  ├─ NAT Gateways         │  ├─ SNS Alerts Topic                                 │
│  ├─ Network Firewall     │  ├─ Secrets Manager (supplier credentials)            │
│  ├─ VPC Endpoints        │  └─ S3 Buckets (deployment artifacts)                │
│  ├─ VPC Flow Logs        │                                                      │
│  ├─ Route53 (public +    │  aurora-postgres/                                    │
│  │  private zones, DNSSEC│  ├─ Aurora PostgreSQL Serverless v2                  │
│  │  DNS query logging)   │  └─ Security Group (CIDR + SG rules)                 │
│  ├─ NACLs                │                                                      │
│  └─ DB Subnet Group      │  ecs/ (ECS Cluster)                                  │
│                          │  ├─ ECS Fargate Cluster + shared ALB                 │
│                          │  └─ Service Discovery Namespace                       │
└─────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────┐
│                           PER-ENVIRONMENT RESOURCES                              │
│  (hometest-app — deployed per environment: dev, uat, demo, prod)                │
├─────────────────────────────────────────────────────────────────────────────────┤
│  CloudFront + S3 (SPA)                                                          │
│  {env}.{account}.hometest.service.nhs.uk ───► S3 Bucket (Next.js SPA)           │
│                                                                                  │
│  API Gateway (REST v1) — one per lambda with api_path_prefix                    │
│  /eligibility-lookup/*   ───► eligibility-lookup-lambda                          │
│  /login/*                ───► login-lambda (NHS Login auth)                      │
│  /session/*              ───► session-lambda (auth cookie validation)            │
│  /order/* (POST)         ───► order-service-lambda (create orders)               │
│  /get-order/* (GET)      ───► get-order-lambda (retrieve orders)                 │
│  /result/*               ───► order-result-lambda (receive supplier results)     │
│  /results/* (GET)        ───► get-results-lambda (retrieve test results)         │
│  /test-order-status/*    ───► order-status-lambda (update order status)          │
│  /postcode-lookup/*      ───► postcode-lookup-lambda (OS Places API)             │
│                                                                                  │
│  SQS Queues (per-environment, KMS-encrypted with pii_data key)                  │
│  order-placement         ◄── order-service-lambda (enqueues orders)              │
│  order-placement         ───► order-router-lambda (SQS-triggered, routes to      │
│                               supplier)                                          │
│  notify-messages         ◄── order-result-lambda, order-status-lambda            │
│  order-results           ◄── order-result-lambda                                 │
│  notifications (FIFO)    (ordered notification delivery)                         │
│  events                  ───► SQS-triggered lambdas                              │
│                                                                                  │
│  Lambda Functions (Node.js 24.x, arm64)                                         │
│  ├─ eligibility-lookup-lambda   (eligibility info, DB access)                   │
│  ├─ login-lambda                (NHS Login authentication)                      │
│  ├─ session-lambda              (auth cookie validation, user info)              │
│  ├─ order-service-lambda        (create orders, enqueue to SQS)                 │
│  ├─ get-order-lambda            (retrieve order details from DB)                │
│  ├─ order-router-lambda         (SQS-triggered, routes to supplier APIs)        │
│  ├─ order-result-lambda         (receive results from suppliers, Cognito auth)  │
│  ├─ get-results-lambda          (retrieve test results from DB)                 │
│  ├─ order-status-lambda         (update order status, Cognito auth)             │
│  └─ postcode-lookup-lambda      (address lookup via OS Places API)              │
│                                                                                  │
│  Lambda Goose Migrator (per-environment schema migrations)                      │
│  └─ Creates hometest_{env} schema + app_user_{env} in shared Aurora             │
│                                                                                  │
│  WireMock (optional, ECS Fargate — enabled per env via env.hcl)                 │
│  └─ Stubs 3rd-party APIs for dev/test; routed via shared ALB or dedicated ALB   │
└─────────────────────────────────────────────────────────────────────────────────┘
```

## KMS Key Layout

| Key | Location | Purpose |
|-----|----------|---------|
| **tfstate** | bootstrap | Terraform state encryption |
| **logs** | bootstrap | All log encryption (S3 access logs, VPC flow logs, DNS query logs) |
| **main** | shared_services | General app encryption (CloudWatch, Lambda env vars, S3, CloudFront, secrets) |
| **pii_data** | shared_services | PII data (Aurora storage + master secret, SQS queues, app_user secret) |

## Directory Structure

```text
infrastructure/
├── environments/
│   ├── _envcommon/
│   │   ├── all.hcl                     # Global config (region, project, GitHub, Cognito)
│   │   ├── hometest-app.hcl            # Shared hometest-app settings + build hooks
│   │   └── goose-migrator.hcl          # Shared goose-migrator settings
│   ├── root.hcl                        # Root Terragrunt config (S3 backend, tags)
│   ├── poc/                            # POC account (781863586270)
│   │   ├── account.hcl                 # AWS account settings
│   │   ├── terragrunt.hcl              # POC account coordination (skip=true)
│   │   ├── core/
│   │   │   ├── env.hcl                 # environment = "core"
│   │   │   ├── bootstrap/              # S3 state backend, GitHub OIDC
│   │   │   ├── network/                # VPC, Route53, Firewall, Endpoints
│   │   │   ├── shared_services/        # WAF, ACM, KMS, Cognito, IAM, SNS, Secrets
│   │   │   ├── aurora-postgres/        # Aurora PostgreSQL Serverless v2
│   │   │   ├── ecs/                    # ECS Fargate Cluster + shared ALB
│   │   │   └── rds-postgres/           # (placeholder)
│   │   └── hometest-app/
│   │       ├── app.hcl                 # Account-level app config (secrets, NHS Login)
│   │       ├── dev/                    # Dev environment
│   │       │   ├── env.hcl             # Domain overrides, feature flags
│   │       │   ├── app/                # hometest-app stack
│   │       │   └── lambda-goose-migrator/  # Per-env DB migrations
│   │       ├── uat/                    # UAT environment (WireMock enabled)
│   │       ├── demo/                   # Demo environment
│   │       ├── prod/                   # Production environment
│   │       └── dev-example/            # Example for new developer environments
│   └── dev/                            # DEV account (781195019563)
│       ├── account.hcl                 # AWS account settings
│       ├── core/
│       │   ├── bootstrap/
│       │   ├── network/
│       │   ├── shared_services/
│       │   └── aurora-postgres/
│       └── hometest-app/
│           ├── app.hcl
│           └── staging/                # Staging environment
├── modules/                            # Reusable Terraform modules
│   ├── api-gateway/                    # API Gateway REST API with custom domain
│   ├── cloudfront-spa/                 # CloudFront + S3 for SPA with routing
│   ├── deployment-artifacts/           # S3 bucket for Lambda packages
│   ├── developer-iam/                  # Developer deploy role with scoped policies
│   ├── lambda/                         # Lambda function with placeholder support
│   ├── lambda-iam/                     # Lambda execution role + policies
│   ├── aurora-postgres/                # Aurora PostgreSQL via community module
│   ├── sns/                            # SNS topics with subscriptions
│   ├── sqs/                            # SQS queues with DLQ + CloudWatch alarms
│   └── waf/                            # WAFv2 Web ACL with managed rules
└── src/                                # Terraform root modules (composed from modules/)
    ├── bootstrap/                      # State backend + GitHub OIDC bootstrap
    ├── network/                        # VPC, subnets, firewall, Route53, endpoints
    ├── shared_services/                # WAF, ACM, KMS, Cognito, IAM, SNS, Secrets
    ├── aurora-postgres/                # Aurora PostgreSQL Serverless v2 instance
    ├── ecs-cluster/                    # ECS Fargate cluster + shared ALB + service discovery
    ├── lambda-goose-migrator/          # Goose database migrator Lambda (per-env)
    ├── hometest-app/                   # Per-environment app (Lambda, API GW, CF, SQS, WireMock)
    ├── mock-service/                   # (placeholder for mock service)
    └── rds-postgres/                   # (placeholder for RDS PostgreSQL)
```

## Prerequisites

| Tool | Required Version | Purpose |
|------|-----------------|---------|
| **Terraform** | >= 1.14.0 | Infrastructure provisioning |
| **Terragrunt** | >= 1.0.0 | DRY multi-environment configuration |
| **AWS CLI** | >= 2.x | AWS interaction |
| **Node.js** | >= 20.x | Building Lambda functions and SPA |
| **Go** | >= 1.26.x | Lambda goose migrator builds |
| **mise** | latest | Tool version management (see `.mise.toml`) |

Install pinned versions via mise:

```bash
mise install
```

## Deployment Order

### 0. Bootstrap (First Time Only)

The bootstrap module creates the S3 backend, KMS key, and GitHub OIDC role. It uses local state initially.

```bash
cd infrastructure/src/bootstrap
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
terraform init
terraform apply
```

See [bootstrap README](infrastructure/src/bootstrap/README.md) for state migration instructions.

### 1. Deploy Core Infrastructure

```bash
# Network (VPC, Route53, Firewall, NAT, Security Groups, VPC Endpoints)
cd infrastructure/environments/poc/core/network
terragrunt apply

# Shared Services (WAF, ACM, KMS, Cognito, Developer IAM, SNS, Secrets)
cd ../shared_services
terragrunt apply

# Aurora PostgreSQL (depends on network)
cd ../aurora-postgres
terragrunt apply

# ECS Cluster + shared ALB (depends on network, shared_services)
cd ../ecs
terragrunt apply
```

### 2. Deploy Application Environments

Each environment has two stacks: `lambda-goose-migrator` (DB migrations) and `app` (the main application):

```bash
# Deploy dev environment — database migrations first
cd infrastructure/environments/poc/hometest-app/dev/lambda-goose-migrator
terragrunt apply

# Then the application stack
cd ../app
terragrunt apply

# Or deploy everything at once (respects dependency order)
cd infrastructure/environments/poc
terragrunt run-all apply
```

### Adding New Environments

To add a new environment (e.g. `staging`), see `dev-example/` as a template:

1. Create `infrastructure/environments/poc/hometest-app/staging/env.hcl`:

   ```hcl
   locals {
     environment = "staging"

     # Optional domain overrides (defaults to {env}.poc.hometest.service.nhs.uk)
     # env_domain = "staging.hometest.service.nhs.uk"
     # api_domain = "api.staging.hometest.service.nhs.uk"
     # create_cloudfront_certificate = true
     # create_api_certificate        = true

     # Optional WireMock
     # enable_wiremock = true
   }
   ```

2. Create `app/terragrunt.hcl` and `lambda-goose-migrator/terragrunt.hcl` — copy from `dev/` and adjust.

3. Deploy:

   ```bash
   cd staging/lambda-goose-migrator && terragrunt apply
   cd ../app && terragrunt apply
   ```

## Environments

| Account | Account ID | Short Name | Environments |
|---------|-----------|------------|--------------|
| **POC** | 781863586270 | poc | dev, uat, demo, prod, dev-example |
| **DEV** | 781195019563 | dev | staging |

Domain pattern: `{env}.{account_shortname}.hometest.service.nhs.uk` (default, using shared wildcard cert)

Environments can override domains in `env.hcl` for custom certs (e.g., `dev.hometest.service.nhs.uk`).

Each environment gets its own database schema (`hometest_{env}`) and app user (`app_user_hometest_{env}`) in the shared Aurora cluster via IAM auth.

## Dependencies

The hometest-app deployments depend on outputs from:

| Dependency | Outputs Used |
|------------|--------------|
| **network** | `vpc_id`, `private_subnet_ids`, `public_subnet_ids`, `lambda_security_group_id`, `lambda_rds_security_group_id`, `route53_zone_id` |
| **shared_services** | `kms_key_arn`, `pii_data_kms_key_arn`, `sns_alerts_topic_arn`, `waf_regional_arn`, `waf_cloudfront_arn`, `acm_regional_certificate_arn`, `acm_cloudfront_certificate_arn`, `cognito_user_pool_arn` |
| **aurora-postgres** | `cluster_endpoint`, `cluster_port`, `cluster_database_name`, `cluster_resource_id`, `cluster_master_user_secret_arn` |
| **ecs** (when WireMock enabled) | `cluster_arn`, `cluster_name`, `alb_dns_name`, `alb_zone_id`, `alb_security_group_id`, `alb_https_listener_arn`, `service_discovery_namespace_id` |

## Shared vs Per-Environment Resources

### Shared (in `core/`)

| Resource | Why Shared |
|----------|------------|
| **VPC & Subnets** | Same network for all environments |
| **Network Firewall** | Centralized egress filtering |
| **VPC Endpoints** | Shared private connectivity to AWS services |
| **Route53 Zones** | Single DNS zone with DNSSEC |
| **KMS Keys** (main + pii_data) | Separate keys for general and PII encryption |
| **WAF Web ACLs** | Consistent security rules across API Gateway, CloudFront, ALB |
| **ACM Certificates** | Wildcard covers all subdomains |
| **Cognito** | Shared user pool and identity pool |
| **Developer IAM** | Single role for all deployments |
| **Aurora PostgreSQL** | Shared database (schema-per-environment isolation) |
| **ECS Cluster + ALB** | Shared Fargate cluster and ALB for WireMock / container workloads |
| **SNS Alerts Topic** | Shared alerting for CloudWatch alarms |

### Per-Environment (in `hometest-app/{env}/`)

| Resource | Why Per-Environment |
|----------|---------------------|
| **Lambda Functions** | Different code versions per env |
| **API Gateways** | Separate endpoints per env |
| **CloudFront + S3** | Separate SPA distributions per env |
| **SQS Queues** | Separate message queues per env (order-placement, notify-messages, order-results, notifications, events) |
| **Route53 Records** | Environment-specific DNS |
| **Lambda Goose Migrator** | Per-env schema + app_user in shared Aurora |
| **WireMock** (optional) | Per-env mock service on shared ECS cluster |

## Security Features

### Network Security

- **VPC** with public, private, firewall, and data subnets
- **Network Firewall** with strict-order stateful rules, domain filtering, and IP filtering
- **NACLs** with port restrictions on private and data subnets
- **Security Groups** with least-privilege rules (Lambda, Lambda-RDS, Aurora, VPC Endpoints)
- **NAT Gateways** for outbound internet access from private subnets
- **VPC Endpoints** for private connectivity (S3, Lambda, Secrets Manager, SQS, KMS, CloudWatch, ECR)

### WAF Protection

- AWS Managed Rules (CommonRuleSet, SQLi, KnownBadInputs, IP Reputation, Anonymous IP)
- Rate limiting (2000 requests/5 min per IP)
- Geo blocking support
- IP allow list support
- Separate WAFs for API Gateway (regional), CloudFront (global), and ALB (regional)
- CloudWatch logging with field redaction

### Encryption

- **KMS `main` key** — Lambda env vars, S3, CloudWatch, CloudFront, general secrets
- **KMS `pii_data` key** — Aurora storage + master secret, SQS queues, app_user secrets
- **KMS `tfstate` key** — Terraform state files
- **KMS `logs` key** — S3 access logs, VPC flow logs, DNS query logs, Network Firewall logs
- **TLS 1.2+** for all endpoints
- **HTTPS only** with HTTP redirect
- **DNSSEC** on Route53 zones

### Access Control

- **GitHub OIDC** — no long-lived AWS credentials
- **MFA support** for developer role (configurable)
- **Permissions boundaries** to prevent privilege escalation
- **Scoped IAM policies** with explicit denies for dangerous actions
- **Cognito User Pools** — authorizer on selected API Gateway endpoints (result, test-order-status)
- **Aurora IAM authentication** — Lambdas connect to database without passwords

### Database Security

- **VPC-only access** via data subnets
- **Security group** restricting ingress to allowed CIDRs and Lambda-RDS SG
- **AWS-managed master user secret** in Secrets Manager
- **Encryption at rest** via KMS `pii_data` key
- **Schema-per-environment** isolation (`hometest_dev`, `hometest_uat`, etc.)
- **IAM-authenticated app users** — one per env (`app_user_hometest_{env}`)

## Outputs

After deploying hometest-app, you get:

| Output | Description |
|--------|-------------|
| `lambda_functions` | Map of all Lambda function details (name, ARN, invoke ARN) |
| `api_gateways` | Map of API Gateway details per prefix (ID, execution ARN, invoke URL) |
| `spa_url` | SPA frontend URL |
| `spa_bucket_id` | S3 bucket ID for SPA static assets |
| `cloudfront_distribution_id` | For cache invalidation |
| `login_endpoint` | Login Lambda endpoint URL |
| `environment_urls` | All environment URLs (base, UI, API, per-prefix) |
| `deployment_info` | CI/CD deployment info (bucket, CF ID, lambda list, API prefixes) |
| `wiremock_url` | WireMock URL (when enabled) |
| `wiremock_admin_url` | WireMock admin URL (when enabled) |

## Troubleshooting

### Dependencies not resolved

```bash
# Run with explicit dependency fetching
terragrunt apply --terragrunt-fetch-dependency-output-from-state
```

### Certificate validation pending

```bash
# Check certificate status
aws acm describe-certificate --certificate-arn <ARN> --query 'Certificate.Status'
```

### WAF not attached

```bash
# Verify WAF association
aws wafv2 list-resources-for-web-acl --web-acl-arn <ARN> --resource-type API_GATEWAY
```

### Aurora connection issues

```bash
# Check Aurora cluster status
aws rds describe-db-clusters --query 'DBClusters[*].[DBClusterIdentifier,Status]'

# Retrieve master user secret
aws secretsmanager get-secret-value --secret-id <secret-arn>

# Run database migrations manually for a specific environment
cd infrastructure/environments/poc/hometest-app/dev/lambda-goose-migrator
terragrunt apply
```

### Lambda build failures

The `hometest-app.hcl` envcommon includes build hooks that run `npm ci` and `npm run build` before Terraform apply. Ensure the `hometest-service` repo is cloned alongside this repo:

```text
parent-dir/
├── hometest-mgmt-terraform/   (this repo)
└── hometest-service/           (application code)
    ├── lambdas/
    │   └── src/               (lambda source directories)
    ├── ui/                    (Next.js SPA)
    └── tests/                 (Playwright tests, WireMock stubs)
```

### WireMock issues

```bash
# Check ECS service status
aws ecs describe-services --cluster <cluster-name> --services <service-name>

# View WireMock container logs
aws logs tail /ecs/<wiremock-service-name> --follow
```
