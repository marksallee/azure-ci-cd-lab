#!/usr/bin/env bash
# One-time Azure bootstrap for the CI/CD lab. Run after `az login`.
#   usage: scripts/bootstrap-azure.sh <github-owner/repo> [location]
# Creates: Terraform state storage, an Entra app + service principal with
# GitHub OIDC federated credentials (one per environment), role assignments,
# and registers the resource providers Container Apps needs.
# Prints the values to feed into scripts/configure-github.sh.
set -euo pipefail

REPO="${1:?usage: $0 <github-owner/repo> [location]}"
LOCATION="${2:-westus2}"
APP_NAME="cicdlab" # must match var.app_name in infra/variables.tf
APP_DISPLAY_NAME="azure-ci-cd-lab-github"
STATE_RG="rg-${APP_NAME}-tfstate"

# Needs an OWNER-level identity: it creates an Entra app, registers resource
# providers and assigns roles. A scoped Contributor user cannot run this.
SUB_ID="$(az account show --query id -o tsv)"
TENANT_ID="$(az account show --query tenantId -o tsv)"
# Portable SHA-1 (macOS has shasum, most Linux has sha1sum).
sha1() { if command -v sha1sum >/dev/null; then sha1sum; else shasum -a 1; fi; }
# Storage account names: 3-24 chars, lowercase+digits, globally unique.
SA_NAME="st${APP_NAME}$(echo -n "$SUB_ID" | sha1 | cut -c1-10)"

echo ">> Subscription: $SUB_ID  Tenant: $TENANT_ID  Repo: $REPO"

echo ">> Registering resource providers"
for p in Microsoft.App Microsoft.OperationalInsights Microsoft.Storage; do
  az provider register --namespace "$p" --wait
done

echo ">> Terraform state storage ($STATE_RG / $SA_NAME)"
az group create -n "$STATE_RG" -l "$LOCATION" -o none
az storage account create -n "$SA_NAME" -g "$STATE_RG" -l "$LOCATION" \
  --sku Standard_LRS --min-tls-version TLS1_2 --allow-blob-public-access false -o none
az storage container create -n tfstate --account-name "$SA_NAME" --auth-mode login -o none || true

echo ">> Entra app registration + service principal"
APP_ID="$(az ad app list --display-name "$APP_DISPLAY_NAME" --query '[0].appId' -o tsv)"
if [ -z "$APP_ID" ]; then
  APP_ID="$(az ad app create --display-name "$APP_DISPLAY_NAME" --query appId -o tsv)"
fi
az ad sp show --id "$APP_ID" >/dev/null 2>&1 || az ad sp create --id "$APP_ID" -o none

echo ">> Federated credentials (one per GitHub environment)"
for env in dev staging prod; do
  name="github-${env}"
  if az ad app federated-credential list --id "$APP_ID" --query "[?name=='$name'].name" -o tsv | grep -q .; then
    echo "   $name exists"
    continue
  fi
  az ad app federated-credential create --id "$APP_ID" --parameters "{
    \"name\": \"$name\",
    \"issuer\": \"https://token.actions.githubusercontent.com\",
    \"subject\": \"repo:${REPO}:environment:${env}\",
    \"audiences\": [\"api://AzureADTokenExchange\"]
  }" -o none
  echo "   created $name -> repo:${REPO}:environment:${env}"
done

echo ">> Role assignments"
SP_OBJ_ID="$(az ad sp show --id "$APP_ID" --query id -o tsv)"
# Least privilege: one resource group per environment, created here, and the
# CI identity gets Contributor on each group only (not on the subscription).
for env in dev staging prod; do
  rg="rg-${APP_NAME}-${env}"
  az group create -n "$rg" -l "$LOCATION" -o none
  az role assignment create --assignee-object-id "$SP_OBJ_ID" --assignee-principal-type ServicePrincipal \
    --role Contributor --scope "/subscriptions/$SUB_ID/resourceGroups/$rg" -o none || true
  echo "   $rg: Contributor for the CI identity"
done
SA_ID="$(az storage account show -n "$SA_NAME" -g "$STATE_RG" --query id -o tsv)"
az role assignment create --assignee-object-id "$SP_OBJ_ID" --assignee-principal-type ServicePrincipal \
  --role "Storage Blob Data Contributor" --scope "$SA_ID" -o none || true

cat <<EOF

=== Done. Use these with scripts/configure-github.sh ===
export AZURE_CLIENT_ID=$APP_ID
export AZURE_TENANT_ID=$TENANT_ID
export AZURE_SUBSCRIPTION_ID=$SUB_ID
export TFSTATE_RG=$STATE_RG
export TFSTATE_SA=$SA_NAME

Reminder: set your Azure budget alert now, and run the "Destroy lab environment"
workflow (dev, staging, prod) + scripts/teardown-azure.sh when finished.
EOF
