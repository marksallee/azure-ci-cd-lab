# Azure CI/CD lab: dev → staging → prod, plus a non-Azure VM

A small, low-cost reference pipeline that builds one container image and
promotes that exact digest through three Azure environments, with a manual
approval gate before prod. A self-hosted runner on a VM outside Azure runs the
same image, to show the pipeline is not tied to one cloud.

The application is deliberately tiny so the pipeline is the subject.

```text
push to main
   │
 build ── test, build multi-arch image, push to GHCR, output image@sha256:digest
   │
 dev ───── terraform apply (Azure Container Apps) + smoke test      [auto]
   │
 staging ─ terraform apply + smoke test                             [auto]
   │
 homelab ─ docker compose on a VM via self-hosted runner           [auto, optional]
   │
 prod ──── ⏸ required reviewer approves ─► terraform apply + smoke   [manual gate]
```

Every smoke test calls `/version` and checks that it returns the commit SHA that
was just deployed, so each stage proves which build is running where.

## What it demonstrates

- GitHub Actions with **environments**, a **required-reviewer approval gate**, and a **reusable workflow** shared by all three Azure stages
- **Build once, promote the artifact**: prod runs the digest that passed staging, never a rebuild
- **OIDC federation** from GitHub to Entra ID, with no stored cloud secrets
- **Terraform** with one state file per environment and per-environment tfvars
- A **self-hosted runner** deploying the same image to a non-Azure VM
- A **multi-arch image** (`linux/amd64` + `linux/arm64`) and a small **.NET** build/test job showing the same pipeline pattern for another stack
- **Cost guardrails**: scale to zero, a Log Analytics daily cap, and one-click destroy

## Repository layout

| Path | Purpose |
|---|---|
| `app/` | Stdlib-only Python service (`/healthz`, `/version`) and unit tests |
| `Dockerfile` | Non-root image with a healthcheck |
| `infra/` | Terraform: Log Analytics (daily cap) and a Container Apps environment and app. `envs/*.tfvars` hold the per-environment differences |
| `.github/workflows/ci.yml` | Pull-request and branch checks: tests, `terraform fmt/validate`, docker build, .NET tests |
| `.github/workflows/cd.yml` | Build once, then dev → staging → homelab → prod |
| `.github/workflows/_deploy-azure.yml` | Reusable deploy job used for all three environments |
| `.github/workflows/destroy.yml` | Manual teardown per environment (type `DESTROY` to confirm) |
| `dotnet/` | Minimal .NET library and xunit tests |
| `deploy/homelab/` | `compose.yaml` and `install-runner.sh` for the non-Azure VM |
| `scripts/` | Local checks, one-time Azure bootstrap, GitHub environment setup, final teardown |
| `docs/SETUP.md` | Step-by-step setup, security notes, cost and teardown |

## Quick start (no cloud account needed)

```bash
scripts/local-check.sh                         # unit tests, local docker build and run
cd infra && terraform init -backend=false      # downloads the provider, makes no Azure calls
terraform fmt -check -recursive && terraform validate
```

Pushing the repo to GitHub runs `ci.yml` for free on a public repo. Deploying to
Azure is a separate, optional step: see [docs/SETUP.md](docs/SETUP.md).

## Design decisions

- **Why Container Apps:** consumption pricing, scale to zero, and no cluster to operate. That keeps the focus on the pipeline.
- **Why GHCR:** the image lives next to the code, and a public package lets Azure pull it without registry credentials.
- **Why OIDC:** the federated credential subject is `repo:<owner>/<repo>:environment:<env>`, so only a job bound to that GitHub environment can obtain an Azure token. There is nothing to rotate or leak.
- **Why the gate lives on the environment:** the same job pauses in prod and runs straight through in dev. Reviewers, branch restrictions and wait timers are configured in one place instead of in YAML.
- **Why state per environment:** `dev.tfstate`, `staging.tfstate` and `prod.tfstate` in Azure Storage with Entra auth, so a bad apply in one environment cannot touch another.
- **Least privilege:** the CI identity has Contributor on its own environment's resource group only. Resource providers are registered once during bootstrap, so the provider block sets `resource_provider_registrations = "none"`.
- **Non-Azure target:** the runner makes an outbound-only connection, so the VM needs no inbound firewall rules.

## Known limitations and next steps

- One service principal with three federated credentials; a real team would use a separate identity (and ideally a subscription) per environment.
- No `terraform plan` review step before the prod approval, and `prevent_self_review` is off because this is a one-person lab.
- No vulnerability scan, SBOM or image signing yet, and actions are pinned by tag, not by commit SHA.
- No automatic rollback on a failed smoke test (Container Apps revisions would make this straightforward).
- Prod scales to zero here to save money, so its first request has a cold start. A real prod would keep one replica.

## Status

CI (Python tests, `terraform fmt/validate`, docker build, .NET tests) passes on
GitHub. The Azure deployment path and the self-hosted runner have not been
exercised end to end yet; this section will be updated when they have.
