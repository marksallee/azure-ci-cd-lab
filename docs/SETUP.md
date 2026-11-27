# Setup, security and teardown

Follow these in order. Nothing in the repo pushes code or creates cloud
resources on its own; each script is run by you.

## 0. Free checks first (no Azure account)

```bash
scripts/local-check.sh                         # unit tests, local docker build and run
cd infra && terraform init -backend=false      # downloads the provider, makes no Azure calls
terraform fmt -check -recursive && terraform validate
cd ..
dotnet test dotnet/BuildInfo.Tests             # needs the .NET 10 SDK; CI runs it anyway
```

Push the repo and let `ci.yml` run. On `main`, `cd.yml` builds and tests, but the
Azure stages are skipped until the repo variable `ENABLE_AZURE` is `true` (step 4
sets it), and the VM stage is skipped until `ENABLE_HOMELAB` is `true`. So a push
never creates cloud resources by surprise.

## 1. GitHub repository

Make the repo **public**, or use GitHub Pro/Team: required-reviewer approval
gates on private repos need a paid plan. Read the security notes below before
using a public repo with a self-hosted runner.

## 2. Azure budget alert

Cost Management → Budgets, for example $10/month with email alerts at 50% and
100%. A budget only alerts; it does not stop spending.

## 3. Bootstrap Azure (about 10 minutes)

Check region capacity first and register the Container Apps provider if needed.
Then run as an **owner-level** account, because the script creates an Entra app
and registers providers:

```bash
az login
scripts/bootstrap-azure.sh <owner>/<repo>
```

It creates Terraform state storage, one resource group per environment, an Entra
app with GitHub OIDC federated credentials (no secrets), and Contributor on
**each environment's resource group only**, then prints `export` lines. The
default region is `westus2`; pass another region as the second argument.

## 4. Configure GitHub

Paste the exports from step 3, then:

```bash
gh auth login
scripts/configure-github.sh <owner>/<repo>
```

This creates the `dev`, `staging`, `prod` and `homelab` environments, makes the
current user the prod reviewer, restricts deploys to `main`, and sets the repo
variables.

## 5. Deploy

Push to `main`. dev and staging deploy automatically; prod waits for approval in
the Actions UI. If the GHCR package is private, make it public (Package
settings → Change visibility) so Azure can pull it.

## 6. Add the non-Azure VM (optional)

Using Proxmox? Follow [deploy/homelab/proxmox-lxc.md](../deploy/homelab/proxmox-lxc.md),
which covers the container, the runner and the lock-down steps. The generic
version is below.

1. On your workstation, get a registration token (valid about an hour):
   `gh api -X POST repos/<owner>/<repo>/actions/runners/registration-token --jq .token`
2. On the VM (Debian/Ubuntu with Docker and the compose plugin):
   `deploy/homelab/install-runner.sh <owner>/<repo> <token>`
3. Once the runner shows as online in the repo's settings:
   `gh variable set ENABLE_HOMELAB --repo <owner>/<repo> --body true`
4. Re-run the workflow. The `homelab` job pulls the same image digest and serves
   it on port 8081.

## Security notes

- A self-hosted runner executes whatever workflow code reaches it. The `homelab`
  job only runs on pushes to `main` (never pull requests) and its environment is
  limited to `main`. On a **public** repo also set Settings → Actions →
  "Require approval for all outside collaborators", and prefer an isolated VM.
- The VM only needs outbound HTTPS to GitHub and GHCR.
- Never commit kubeconfig files, state files or credentials; the `.gitignore`
  excludes the common ones.

## Cost and teardown

Expect cents to a few dollars for a week or two: Container Apps consumption
pricing (all environments scale to zero), Log Analytics capped at 0.1 GB/day,
and a small storage account.

When finished:

1. Run the **Destroy lab environment** workflow for `dev`, `staging` and `prod` (prod needs approval).
2. Run `scripts/teardown-azure.sh`. It deletes every `rg-cicdlab-*` resource group and the Entra app.
3. Remove the runner on the VM: `./config.sh remove --token <token>`.
4. Confirm in the Azure portal that no `rg-cicdlab-*` groups remain.
