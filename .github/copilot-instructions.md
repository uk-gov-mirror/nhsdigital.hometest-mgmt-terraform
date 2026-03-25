# GitHub Copilot Instructions

This repository contains Terraform/Terragrunt infrastructure code for the NHS Hometest service deployed to AWS.

## Project Structure

- `infrastructure/src/` - Terraform root modules (bootstrap, network, aurora-postgres, shared_services, hometest-app, lambda-goose-migrator)
- `infrastructure/modules/` - Reusable Terraform modules (lambda, api-gateway, aurora-postgres, cloudfront-spa, sqs, waf, etc.)
- `infrastructure/environments/` - Terragrunt environment configurations (poc/core, poc/hometest-app)
- `scripts/` - Shell scripts for testing, Docker, reports, and automation
- `.github/workflows/` - GitHub Actions CI/CD pipelines (multi-stage: commit → test → build → acceptance → publish/deploy)
- `.github/actions/` - 12 reusable composite GitHub Actions

## Technology Stack

- **IaC**: Terraform 1.14.7, Terragrunt 0.99.4
- **Cloud**: AWS (Lambda, API Gateway, Aurora PostgreSQL Serverless v2, CloudFront, SQS, WAF, Network Firewall, Route53, Cognito, ACM, KMS)
- **CI/CD**: GitHub Actions (multi-stage pipelines with reusable workflows)
- **Tool Management**: mise (manages all tool versions via `.mise.toml`)
- **Security Scanning**: Trivy v0.69.3, Checkov 3.2.510, Gitleaks 8.30.1
- **Linting**: TFLint 0.61.0 (with AWS plugin), terraform-docs 0.21.0, ShellCheck, yamllint, markdownlint-cli, SQLFluff, actionlint, Vale, EditorConfig
- **Database Migrations**: Goose v3.27.0 (pressly/goose, Go-based)
- **Languages**: Python 3.14.3, Go 1.26.1, Node.js
- **Pre-commit**: 16 hook repos covering formatting, linting, security, and validation
- **AWS CLI**: 2.34.15

## Verifying Changes

**Always use Terragrunt — never run the `terraform` binary directly.** All infrastructure operations must go through Terragrunt, which wraps Terraform and manages remote state, DRY configuration, dependency ordering, and input validation.

### Local Verification Workflow

1. **Install tools**: `mise install`
2. **Run all pre-commit checks**: `mise run pre-commit` — this runs all 16 hook repos in one go
3. **Plan changes with Terragrunt**:

   ```bash
   cd infrastructure/environments/poc/<module-path>
   terragrunt init
   terragrunt plan
   ```

4. **Test DB migrations** (if SQL changes): `mise run test-migrations`

### What Pre-commit Checks (via `mise run pre-commit`)

The pre-commit suite runs the following checks, which are identical to what the CI pipeline enforces:

#### File & Format Checks

- **trailing-whitespace** — Remove trailing whitespace (preserve Markdown line breaks)
- **end-of-file-fixer** — Ensure files end with a newline
- **check-yaml** — Validate YAML syntax (allows multiple documents)
- **check-json** — Validate JSON syntax
- **check-toml** — Validate TOML syntax
- **check-added-large-files** — Block files > 500KB
- **check-case-conflict** — Detect case-insensitive filename collisions
- **check-merge-conflict** — Detect merge conflict markers
- **check-symlinks** — Detect broken symlinks
- **check-executables-have-shebangs** — Enforce shebangs on executables
- **mixed-line-ending** — Enforce LF line endings
- **no-commit-to-branch** — Block direct commits to main/master/develop
- **EditorConfig** — Validate file formatting against `.editorconfig` (runs in CI via `check-file-format` action)

#### Terraform & Terragrunt Checks

- **terraform_fmt** — Format all Terraform files under `infrastructure/` (recursive)
- **terragrunt_fmt** — Format all Terragrunt files under `infrastructure/environments/`
- **terraform_tflint** — Lint Terraform modules under `infrastructure/src/` using `.tflint.hcl` config (AWS plugin enabled, parallelism=4)
- **terraform_trivy** — Scan Terraform code for misconfigurations, vulnerabilities, and secrets using `trivy.yaml` config
- **terragrunt_validate_inputs** — Validate Terragrunt inputs for each module (bootstrap, network, shared_services, aurora-postgres, lambda-goose-migrator, dev) with strict validation
- **terraform_docs** — Auto-generate README.md documentation for Terraform modules
- **terraform_checkov** — Run Checkov security scanning against `infrastructure/src/` using `.checkov.yaml` config (hard-fail on CRITICAL/HIGH)

#### Language & Content Linting

- **yamllint** — Lint all YAML files
- **markdownlint** — Lint Markdown files with auto-fix (excludes `infrastructure/src/`)
- **sqlfluff-lint** / **sqlfluff-fix** — Lint and auto-fix SQL files using `.sqlfluff` config
- **actionlint** — Lint GitHub Actions workflow files
- **shellcheck** — Lint shell scripts (severity=warning)

#### Security Scanning

- **gitleaks** — Detect secrets and credentials using custom config at `scripts/config/gitleaks.toml`
- **detect-private-key** — Detect committed private keys

### CI Pipeline Verification (GitHub Actions)

The CI pipeline runs these stages on every PR:

1. **Stage 1 — Commit Stage** (`stage-1-commit.yaml`):
   - EditorConfig file format check
   - Lines of code report (CLOC) uploaded to S3
   - Dependency scanning (SBOM + vulnerability reports) uploaded to S3
   - Full pre-commit suite (all hooks listed above)

2. **Stage 2 — Test Stage** (`stage-2-test.yaml`):
   - **Terragrunt Plan** for all modules in parallel via matrix strategy: `core/bootstrap`, `core/network`, `core/aurora-postgres`, `core/shared_services`, `hometest-app/dev`, `hometest-app/dev/lambda-goose-migrator`
   - **Goose migration tests** against PostgreSQL in Docker (schema creation, role privileges, idempotency)
   - SonarCloud static analysis (when credentials available)

3. **Stage 3 — Build** (`stage-3-build.yaml`): Artefact building (placeholder)

4. **Stage 4 — Acceptance** (`stage-4-acceptance.yaml`): Contract, security, UI, performance, integration, accessibility, load tests (placeholder)

### Deployment Pipelines

- **cicd-3-deploy.yaml** — Auto-deploys core modules sequentially on push to main: bootstrap → network → aurora-postgres → shared_services
- **deploy-tf-core.yaml** — Manual dispatch for core infrastructure modules with optional Lambda goose-migrator invocation and CloudWatch log polling
- **deploy-tf-hometest-app.yaml** — Manual dispatch for hometest-app deployment with environment/sub-environment selection, goose-migrator, and destroy path

All deployments use the `deploy-terragrunt` composite action which runs `mise exec -- terragrunt init/plan/apply` with AWS OIDC authentication.

## Code Style Guidelines

### Terraform

- Use `terraform fmt` for formatting (enforced by pre-commit)
- Follow AWS provider naming conventions
- Use snake_case for resource names and variables
- Include descriptions for all variables and outputs
- Tag all AWS resources with standard tags: Owner, CostCenter, Project, Environment, ManagedBy, Repository (defined in `root.hcl`)
- Use modules from `infrastructure/modules/` for reusable components
- Auto-generate module docs with `terraform-docs` (injected into README.md between `<!-- BEGIN_TF_DOCS -->` markers)

### Terragrunt

- Keep DRY with `root.hcl` includes and `_envcommon/` shared variable files
- Use `dependency` blocks for cross-module references
- Validate inputs with `terragrunt_validate_inputs` (strict mode enabled)
- Format with `terragrunt fmt` (enforced by pre-commit)
- **When adding a new Terraform root module**: add a corresponding `terragrunt_validate_inputs` hook entry in `.pre-commit-config.yaml` with the correct `files` regex pattern for the new module path, and add the module to the `stage-2-test.yaml` matrix for CI Terragrunt Plan coverage
- Remote state: S3 bucket `nhs-hometest-${environment}-core-s3-tfstate` with KMS encryption
- State key pattern: `${account_name}-${environment}-${module_name}.tfstate`
- Lockfile enabled, parallelism set to 20

### Shell Scripts

- Use `#!/bin/bash` shebang
- Enable strict mode: `set -euo pipefail`
- Pass ShellCheck with severity=warning (enforced by pre-commit)
- Use functions for reusable code
- Include usage documentation in script headers

### SQL

- Must pass SQLFluff linting and auto-fix rules (config in `.sqlfluff`)

### GitHub Actions

- Quote all shell variables: `"$GITHUB_OUTPUT"`, `"$GITHUB_STEP_SUMMARY"`
- Use grouped redirects: `{ echo "..."; } >> "$GITHUB_OUTPUT"`
- Use parameter expansion over sed: `${GITHUB_REF#refs/heads/}`
- Use action `install-mise` for tool installation
- Define inputs for reusable workflows
- Must pass actionlint validation (enforced by pre-commit)
- Workflows follow naming convention: `cicd-N-*.yaml` for pipeline stages, `stage-N-*.yaml` for reusable stage workflows, `deploy-tf-*.yaml` for deployment workflows

### Markdown & YAML

- Markdown must pass markdownlint with auto-fix
- YAML must pass yamllint validation
- Both enforced by pre-commit

## Security Considerations

- Never commit secrets or credentials
- Use AWS IAM roles with OIDC for GitHub Actions (no static keys)
- Gitleaks runs in pre-commit with custom config at `scripts/config/gitleaks.toml`
- Trivy scans for vulnerabilities, misconfigurations, and secrets (exit code 1 on CRITICAL)
- Checkov hard-fails on CRITICAL and HIGH severity findings
- TFLint uses AWS plugin with recommended preset
- Use `.gitleaksignore` for false positives
- Follow NHS security guidelines
- Dependency SBOM and vulnerability reports uploaded to S3

## Common Commands

```bash
# Install all tools (terraform, terragrunt, tflint, trivy, checkov, gitleaks, goose, etc.)
mise install

# Run all pre-commit checks (equivalent to CI Stage 1)
mise run pre-commit

# Test DB migrations against local PostgreSQL in Docker
mise run test-migrations

# Test DB migrations and keep the PostgreSQL container running for inspection
mise run test-migrations-keep

# Clean Terraform/Terragrunt cache directories
mise run tf-clean-cache

# Terragrunt operations — always use Terragrunt, not terraform directly
cd infrastructure/environments/poc/core/network
terragrunt init
terragrunt plan
terragrunt apply

# Terragrunt operations for hometest-app (specific sub-environment)
cd infrastructure/environments/poc/hometest-app/dev
terragrunt init
terragrunt plan
terragrunt apply
```

## AWS Configuration

- Region: eu-west-2 (London)
- Authentication: AWS SSO with OIDC
- Profile: Admin-PoC
- Terraform plugin cache: `.terraform-plugin-cache/` (set via `TF_PLUGIN_CACHE_DIR`)
- Terragrunt experiment: `dependency-fetch-output-from-state` enabled

## Files to Reference

- `.mise.toml` - All tool versions, tasks, and environment variables
- `.pre-commit-config.yaml` - Pre-commit hook configuration (16 repos)
- `.tflint.hcl` - TFLint rules (AWS plugin v0.45.0, recommended preset)
- `.checkov.yaml` - Checkov config (hard-fail CRITICAL/HIGH, frameworks: terraform, terraform_plan, secrets)
- `trivy.yaml` - Trivy config (scanners: vuln, misconfig, secret; severity: CRITICAL)
- `root.hcl` - Terragrunt root configuration (remote state, tags, parallelism)
- `infrastructure/environments/_envcommon/` - Shared Terragrunt variables
- `scripts/config/gitleaks.toml` - Gitleaks custom rules
- `.sqlfluff` - SQLFluff linting configuration
- `.editorconfig` - EditorConfig formatting rules
