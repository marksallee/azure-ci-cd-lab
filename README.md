# Azure CI/CD lab: dev → staging → prod on Azure, plus a non-Azure VM

Build one container image, then promote that exact digest through three Azure
environments with a manual approval gate before prod. A self-hosted runner on a
VM outside Azure runs the same image to show the pipeline isn't tied to a cloud.

```
push to main
   │
 build ── test, build image, push to GHCR, output image@sha256:digest
   │
 dev ───── terraform apply (Azure Container Apps) + smoke test      [auto]
   │
 staging ─ terraform apply + smoke test                             [auto]
   │
 homelab ─ docker compose on your VM via self-hosted runner         [auto, optional]
   │
 prod ──── ⏸ required reviewer approves ─► terraform apply + smoke   [manual gate]
```

Every smoke test calls `/version` and checks it returns the commit SHA that was
just deployed, so each stage proves which build is running where.

## Layout

| Path | Purpose |
|---|---|
| `app/` | Stdlib-only Python service (`/healthz`, `/version`) + unit tests |
| `Dockerfile` | Non-root image with a healthcheck |
| `infra/` | Terraform: RG, Log Analytics (daily cap), Container Apps env + app. `envs/*.tfvars` hold the per-environment differences |
| `.github/workflows/ci.yml` | PR checks: tests, `terraform fmt/validate`, docker build |
| `.github/workflows/cd.yml` | Build once, then dev → staging → homelab → prod |
| `.github/workflows/_deploy-azure.yml` | Reusable deploy job used for all three environments |
| `.github/workflows/destroy.yml` | Manual teardown per environment (type `DESTROY`) |
| `dotnet/` | Minimal .NET library + xunit tests, to show the same pipeline pattern for a .NET project |
| `deploy/homelab/` | `compose.yaml` and `install-runner.sh` for the non-Azure VM |
| `scripts/` | One-time Azure bootstrap, GitHub environment setup, final teardown |

## Step 0: free checks first (no Azure, no GitHub)

Prove the app, image and Terraform syntax work before anything is created in a cloud.

```bash
scripts/local-check.sh                         # unit tests, local docker build and run
cd infra && terraform init -backend=false      # downloads the provider, no Azure calls
terraform fmt -check -recursive && terraform validate
cd ..
dotnet test dotnet/BuildInfo.Tests             # needs the .NET 10 SDK; CI runs it anyway
```

Then, on GitHub only (public repos get free Actions minutes), push and let
`ci.yml` run. The Azure jobs in `cd.yml` fail harmlessly until the Azure
variables exist, so do the Azure setup below only when you are ready for it.

## Setup (about 30 minutes)

Do these in order. Nothing here pushes code for you.

1. **Create the GitHub repo** and push this folder to it. Make the repo
   **public**, or have GitHub Pro/Team: required-reviewer approval gates on
   private repos need a paid plan. Look at "Security notes" below before using
   a public repo with a self-hosted runner.
2. **Set your Azure budget alert** (Cost Management → Budgets), e.g. $10/month
   with email alerts at 50% and 100%.
3. **Bootstrap Azure:** `az login` as an **owner-level** account (it creates an
   Entra app and registers providers; a scoped Contributor user can't), then
   `scripts/bootstrap-azure.sh <owner>/<repo>`. It creates Terraform state
   storage, one resource group per environment, an Entra app with GitHub OIDC
   federated credentials (no secrets), and Contributor on **each environment's
   resource group only**, then prints `export` lines. Default region is
   `westus2`; check capacity for your subscription first.
4. **Configure GitHub:** paste those exports, `gh auth login`, then
   `scripts/configure-github.sh <owner>/<repo>`. It creates the `dev`,
   `staging`, `prod` and `homelab` environments, makes you the prod reviewer,
   restricts deploys to `main`, and sets the repo variables.
5. **Push to `main`.** dev and staging deploy automatically; prod waits for
   your approval in the Actions UI.
6. **Add the non-Azure VM** (optional, but the best demo):
   - On your workstation: `gh api -X POST repos/<owner>/<repo>/actions/runners/registration-token --jq .token`
   - On the VM (Docker installed): `deploy/homelab/install-runner.sh <owner>/<repo> <token>`
   - `gh variable set ENABLE_HOMELAB --repo <owner>/<repo> --body true`
   - Re-run the workflow. The `homelab` job pulls the same image digest and
     serves it on port 8081.
7. If the GHCR package is private, make it public (Package settings → Change
   visibility) so Azure can pull it without registry credentials.

## 5-minute walkthrough

1. Show the diagram above and `cd.yml`: one build job, then the same image digest to every stage.
2. Make a one-line change in `app/server.py`, push to `main`, and watch dev → staging go green.
3. Open the deploy summary and `curl <url>/version` for dev and staging. The SHA matches.
4. Show prod paused on **Review deployments**, approve it, and watch it deploy.
5. Show the homelab job and `curl http://<vm>:8081/version`: same SHA, different platform.
6. Show `_deploy-azure.yml` (one reusable workflow, three environments) and `infra/envs/*.tfvars` (only the differences).

## Key concepts

- **Build once, promote the artifact.** Prod runs the digest that passed staging, never a rebuild.
- **OIDC, no stored secrets.** The federated credential subject is `repo:<owner>/<repo>:environment:<env>`, so only jobs bound to that GitHub environment can get an Azure token.
- **The approval gate lives on the environment**, not in YAML. The same job pauses in prod and runs straight through in dev. Reviewers, branch restrictions and wait timers are configured in one place.
- **Terraform state per environment** (`dev.tfstate`, …) in Azure Storage with Entra auth. Environments differ only through tfvars.
- **Non-Azure target:** the runner makes an outbound-only connection, so the VM needs no inbound firewall rules. The same image and smoke test run there.
- **Cost guardrails:** dev and staging scale to zero, Log Analytics has a daily ingestion cap, budget alert, one-click destroy.

## What I'd improve for a real team

- A separate service principal and subscription per environment (this lab uses one SP with three federated credentials, scoped to one resource group each).
- Show `terraform plan` output for review before the prod approval, and enable `prevent_self_review`.
- Image vulnerability scan and SBOM/signing in the build job; pin actions by SHA.
- Automatic rollback on failed smoke test (Container Apps revisions make this easy).
- Equivalent pipeline for GitHub Enterprise Server, or for .NET/embedded builds. Only the `build` job is language-specific.

## Security notes

- A self-hosted runner executes whatever workflow code reaches it. The `homelab` job only runs on pushes to `main` (never pull requests) and is limited to the `main` branch by its environment, but on a **public** repo also set Settings → Actions → "Require approval for all outside collaborators". Prefer a private repo or an isolated VM.
- The VM only needs outbound HTTPS to GitHub and GHCR.

## Cost and teardown

Expect cents to a few dollars for a week or two: Container Apps consumption pricing
(all environments scale to zero, so prod's first request has a cold start; a real prod would keep one replica), Log Analytics
capped at 0.1 GB/day, and a tiny storage account.

When done:
1. Run **Destroy lab environment** for `dev`, `staging`, `prod` (prod needs your approval).
2. `scripts/teardown-azure.sh` removes the state storage and the Entra app.
3. Remove the runner: `./config.sh remove --token <token>` on the VM.
4. Confirm in the Azure portal that no `rg-cicdlab-*` groups remain.

## Notable design choices

- **Multi-arch image** (`linux/amd64` + `linux/arm64`): one digest, promoted everywhere, runs on cloud hosts, the home-lab VM or ARM boards.
- **Least privilege:** the CI identity has Contributor on its environment's resource group only, and `resource_provider_registrations = "none"` because providers are registered once during bootstrap.
- **Scale to zero everywhere** to keep the lab at close to no cost.

## Validation status

Unit tests pass, and the workflow YAML and shell scripts parse. `terraform
validate`, `az` and the live pipeline could not be run where this was built, so
the first run in your subscription is the real test. Expect small fixes
(provider/API version, region quota) and run `terraform fmt` if `ci.yml` complains.
