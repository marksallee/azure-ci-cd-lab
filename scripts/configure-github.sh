#!/usr/bin/env bash
# Creates the GitHub environments (dev, staging, prod, homelab), the prod
# approval gate, branch restrictions, and the repo variables the workflows read.
#   usage: export AZURE_* TFSTATE_* (from bootstrap-azure.sh), then:
#          scripts/configure-github.sh <owner/repo>
# Requires: gh authenticated with repo admin rights. Run it yourself - it changes
# repo settings but pushes no code.
#
# NOTE: required reviewers on PRIVATE repos need GitHub Pro/Team/Enterprise.
# On a free account the repo must be public for the approval gate to work.
set -euo pipefail

REPO="${1:?usage: $0 <owner/repo>}"
: "${AZURE_CLIENT_ID:?}" "${AZURE_TENANT_ID:?}" "${AZURE_SUBSCRIPTION_ID:?}" "${TFSTATE_RG:?}" "${TFSTATE_SA:?}"

REVIEWER_LOGIN="$(gh api user --jq .login)"
REVIEWER_ID="$(gh api user --jq .id)"
echo ">> Repo: $REPO   Prod reviewer: $REVIEWER_LOGIN"

echo ">> Repo variables"
gh variable set AZURE_CLIENT_ID       --repo "$REPO" --body "$AZURE_CLIENT_ID"
gh variable set AZURE_TENANT_ID       --repo "$REPO" --body "$AZURE_TENANT_ID"
gh variable set AZURE_SUBSCRIPTION_ID --repo "$REPO" --body "$AZURE_SUBSCRIPTION_ID"
gh variable set TFSTATE_RG            --repo "$REPO" --body "$TFSTATE_RG"
gh variable set TFSTATE_SA            --repo "$REPO" --body "$TFSTATE_SA"
# Turns on the dev/staging/prod Azure stages. This script is only run after the
# Azure bootstrap, so enabling them here is the deliberate switch.
gh variable set ENABLE_AZURE          --repo "$REPO" --body "true"
# Flip to "true" once the self-hosted runner on the VM is online.
gh variable set ENABLE_HOMELAB        --repo "$REPO" --body "false"

create_env() { # name, json-body
  echo ">> Environment: $1"
  echo "$2" | gh api --method PUT "repos/$REPO/environments/$1" --input - >/dev/null
  gh api --method POST "repos/$REPO/environments/$1/deployment-branches" -f name=main >/dev/null 2>&1 || true
}

BRANCH_POLICY='"deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true}'

create_env dev      "{$BRANCH_POLICY}"
create_env staging  "{$BRANCH_POLICY}"
create_env homelab  "{$BRANCH_POLICY}"
# prod: manual approval gate. prevent_self_review is false because this is a
# one-person lab - with a team you would set it to true.
create_env prod     "{\"prevent_self_review\":false,\"reviewers\":[{\"type\":\"User\",\"id\":$REVIEWER_ID}],$BRANCH_POLICY}"

echo
echo "Done. Verify under Settings > Environments that prod shows 'Required reviewers'."
