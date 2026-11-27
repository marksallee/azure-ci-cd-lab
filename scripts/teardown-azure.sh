#!/usr/bin/env bash
# Final cleanup AFTER the "Destroy lab environment" workflow has removed
# dev/staging/prod: deletes the state storage RG and the Entra app.
#   usage: scripts/teardown-azure.sh
set -euo pipefail

STATE_RG="rg-cicdlab-tfstate"
APP_DISPLAY_NAME="azure-ci-cd-lab-github"

echo "Lab resource groups that will be deleted:"
az group list --query "[?starts_with(name,'rg-cicdlab')].name" -o tsv

read -r -p "Delete ALL rg-cicdlab-* groups and Entra app '$APP_DISPLAY_NAME'? (type yes) " ans
[ "$ans" = "yes" ] || { echo "aborted"; exit 1; }

for rg in $(az group list --query "[?starts_with(name,'rg-cicdlab')].name" -o tsv); do
  az group delete -n "$rg" --yes --no-wait
done
APP_ID="$(az ad app list --display-name "$APP_DISPLAY_NAME" --query '[0].appId' -o tsv)"
[ -n "$APP_ID" ] && az ad app delete --id "$APP_ID"
echo "Teardown started. Role assignments on the deleted SP are cleaned up automatically."
