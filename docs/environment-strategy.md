# Environment Strategy

This document describes the NHS HomeTest environment strategy, deployment triggers, and intended use for each environment.

## Overview

Each AWS account has its own core infrastructure and application stacks. The POC account includes ECS (WireMock); the Dev account does not.

```text
infrastructure/environments/
├── poc/                         # POC account (deployed by cicd-deploy-poc on merge to main)
│   ├── core/                    # Shared infra: bootstrap → network → shared_services → aurora → ecs
│   │   ├── bootstrap/
│   │   ├── network/
│   │   ├── shared_services/
│   │   ├── aurora-postgres/
│   │   └── ecs/                 # WireMock — POC only
│   └── hometest-app/
│       ├── dev/                 # Live — auto-deployed on merge to main
│       ├── uat/                 # Stubbed — auto-deployed on merge to main
│       ├── demo/                # Stable live — deployed on demand from tags
│       ├── dev-example/         # Template for on-demand dev environments
│       └── dev-{name}/          # On-demand dev environments (created by developers)
└── dev/                         # Dev account (deployed by cicd-deploy-dev on merge to main)
    ├── core/                    # Shared infra: bootstrap → network → shared_services → aurora (no ECS)
    │   ├── bootstrap/
    │   ├── network/
    │   ├── shared_services/
    │   └── aurora-postgres/
    └── hometest-app/
        └── staging/             # Staging — auto-deployed on merge to main
```

---

## Environments

### dev — Live Development

| | |
|---|---|
| **Purpose** | Primary development environment with live (real) external integrations |
| **Deployment** | Automatic on every merge to `main` |
| **Trigger** | `cicd-deploy-poc` workflow (push to `main`) |
| **Integrations** | Live — connects to real external services/APIs |
| **Audience** | Development and QA team |
| **Stability** | Latest code from `main`; may be temporarily unstable after a merge |

### uat — Stubbed User Acceptance Testing

| | |
|---|---|
| **Purpose** | User acceptance testing with stubbed external integrations (WireMock) |
| **Deployment** | Automatic on every merge to `main` |
| **Trigger** | `cicd-deploy-poc` workflow (push to `main`) |
| **Integrations** | Stubbed — uses WireMock (ECS) for external service responses |
| **Audience** | QA team, testers, and developers validating integration contracts |
| **Stability** | Latest code from `main`; isolated from external service variability |

### demo — Stable Live Demo

| | |
|---|---|
| **Purpose** | Stable live environment for showcasing to stakeholders and the product team |
| **Deployment** | On demand only — manually triggered via `deploy-demo` workflow |
| **Source** | Ideally deployed from tagged releases of both `hometest-mgmt-terraform` and `hometest-service` |
| **Integrations** | Live — connects to real external services/APIs |
| **Audience** | Product owners, stakeholders, demos, and sign-off |
| **Stability** | High — only updated deliberately with known-good versions |

To deploy demo, run the `deploy-demo` workflow with:

- **hometest_service_ref**: a tag or specific commit SHA (e.g. `v1.2.0`)
- **action**: `apply`

> **Recommendation:** Tag both repos before deploying to demo so the exact versions are traceable.

### dev-{name} — On-Demand Developer Environments

| | |
|---|---|
| **Purpose** | Isolated environments for individual development and testing |
| **Deployment** | On demand — manually triggered via `deploy-hometest-app` workflow |
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

To deploy, run the `deploy-hometest-app` workflow with:

- **env**: your environment name (e.g. `dev-jane`)
- **action**: `apply`

To tear down when finished:

- **env**: your environment name
- **action**: `destroy`

---

### staging — Staging Environment

| | |
|---|---|
| **Account** | dev |
| **Purpose** | Pre-production staging environment on the Dev AWS account |
| **Deployment** | Automatic on every merge to `main` |
| **Trigger** | `cicd-deploy-dev` workflow (push to `main`) |
| **Integrations** | Live — connects to real external services/APIs |
| **Audience** | QA team and release validation |
| **Stability** | Latest code from `main` |

## Deployment Flow

```text
PR merged to main
  │
  ├─► cicd-deploy-poc (automatic)
  │     ├── Core infra (bootstrap → network → shared_services → aurora → ecs)
  │     ├── dev hometest-app (live)
  │     └── uat hometest-app (stubbed)
  │
  ├─► cicd-deploy-dev (automatic)
  │     ├── Core infra (bootstrap → network → shared_services → aurora — no ECS)
  │     └── staging hometest-app
  │
  └─► Manual workflows
        ├── deploy-demo         ← on demand (from tags, POC account)
        ├── deploy-hometest-app ← on demand (dev-*, any account)
        └── deploy-tf-core      ← on demand (individual core modules)
```

---

## Summary

| Environment | Account | Integration | Deployment Trigger | Source | Stability |
|---|---|---|---|---|---|
| `dev` | poc | Live | Auto on merge to `main` | `main` HEAD | Latest |
| `uat` | poc | Stubbed | Auto on merge to `main` | `main` HEAD | Latest |
| `staging` | dev | Live | Auto on merge to `main` | `main` HEAD | Latest |
| `demo` | poc | Live | Manual (on demand) | Tagged release | High |
| `dev-{name}` | poc | Configurable | Manual (on demand) | Any ref | Varies |
