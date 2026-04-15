# Environment Strategy

This document describes the NHS HomeTest environment strategy, deployment triggers, and intended use for each environment.

## Overview

All environments share core infrastructure (VPC, WAF, ACM, KMS, Cognito, Aurora PostgreSQL, ECS) deployed under `poc/core/`. Each environment deploys its own isolated application stack (Lambdas, API Gateway, CloudFront, SQS, DNS) under `poc/hometest-app/<env>/`.

```text
infrastructure/environments/poc/
├── core/                        # Shared infra (deployed by cicd-3-deploy on merge to main)
│   ├── bootstrap/
│   ├── network/
│   ├── shared_services/
│   ├── aurora-postgres/
│   └── ecs/
└── hometest-app/
    ├── dev/                     # Live — auto-deployed on merge to main
    ├── uat/                     # Stubbed — auto-deployed on merge to main
    ├── demo/                    # Stable live — deployed on demand from tags
    ├── dev-example/             # Template for on-demand dev environments
    └── dev-{name}/              # On-demand dev environments (created by developers)
```

---

## Environments

### dev — Live Development

| | |
|---|---|
| **Purpose** | Primary development environment with live (real) external integrations |
| **Deployment** | Automatic on every merge to `main` |
| **Trigger** | `cicd-3-deploy` workflow (push to `main`) |
| **Integrations** | Live — connects to real external services/APIs |
| **Audience** | Development and QA team |
| **Stability** | Latest code from `main`; may be temporarily unstable after a merge |

### uat — Stubbed User Acceptance Testing

| | |
|---|---|
| **Purpose** | User acceptance testing with stubbed external integrations (WireMock) |
| **Deployment** | Automatic on every merge to `main` |
| **Trigger** | `cicd-3-deploy` workflow (push to `main`) |
| **Integrations** | Stubbed — uses WireMock (ECS) for external service responses |
| **Audience** | QA team, testers, and developers validating integration contracts |
| **Stability** | Latest code from `main`; isolated from external service variability |

### demo — Stable Live Demo

| | |
|---|---|
| **Purpose** | Stable live environment for showcasing to stakeholders and the product team |
| **Deployment** | On demand only — manually triggered via `deploy-tf-hometest-app` workflow |
| **Source** | Ideally deployed from tagged releases of both `hometest-mgmt-terraform` and `hometest-service` |
| **Integrations** | Live — connects to real external services/APIs |
| **Audience** | Product owners, stakeholders, demos, and sign-off |
| **Stability** | High — only updated deliberately with known-good versions |

To deploy demo, run the `deploy-tf-hometest-app` workflow with:

- **subenv**: `demo`
- **action**: `apply`
- **hometest_service_ref**: a tag or specific commit SHA (e.g. `v1.2.0`)

> **Recommendation:** Tag both repos before deploying to demo so the exact versions are traceable.

### dev-{name} — On-Demand Developer Environments

| | |
|---|---|
| **Purpose** | Isolated environments for individual development and testing |
| **Deployment** | On demand — manually triggered via `deploy-tf-hometest-app` workflow |
| **Source** | Any branch, tag, or SHA from either repo |
| **Integrations** | Configurable per environment (live or stubbed) |
| **Audience** | Individual developers |
| **Lifecycle** | Temporary — should be destroyed when no longer needed |

To create a new on-demand environment, follow the [Creating a New Environment](developer-guides/Creating_New_Environment.md) guide. Use the `dev-example` template as a starting point:

```bash
ENV_NAME="dev-jane"
cp -r infrastructure/environments/poc/hometest-app/dev-example \
      infrastructure/environments/poc/hometest-app/${ENV_NAME}
```

To deploy, run the `deploy-tf-hometest-app` workflow with:

- **subenv**: your environment name (e.g. `dev-jane`)
- **action**: `apply`

To tear down when finished:

- **subenv**: your environment name
- **action**: `destroy`

---

## Deployment Flow

```text
PR merged to main
  │
  ├─► cicd-3-deploy (automatic)
  │     ├── Core infra (bootstrap → network → shared_services → aurora → ecs)
  │     └── (dev and uat app deployments to be wired here)
  │
  └─► deploy-tf-hometest-app (manual / future automatic for dev + uat)
        ├── dev     ← auto after merge to main
        ├── uat     ← auto after merge to main
        ├── demo    ← on demand (from tags)
        └── dev-*   ← on demand (by developers)
```

---

## Summary

| Environment | Integration | Deployment Trigger | Source | Stability |
|---|---|---|---|---|
| `dev` | Live | Auto on merge to `main` | `main` HEAD | Latest |
| `uat` | Stubbed | Auto on merge to `main` | `main` HEAD | Latest |
| `demo` | Live | Manual (on demand) | Tagged release | High |
| `dev-{name}` | Configurable | Manual (on demand) | Any ref | Varies |
