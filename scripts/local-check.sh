#!/usr/bin/env bash
# Zero-cost checks you can run before anything touches Azure or GitHub.
# Needs: python3, and optionally docker. Makes no cloud calls and pushes nothing.
#   usage: scripts/local-check.sh
set -euo pipefail
cd "$(dirname "$0")/.."

echo ">> 1/3 Python unit tests"
python3 -m unittest discover -s app/tests -v

if ! command -v docker >/dev/null || ! docker info >/dev/null 2>&1; then
  echo ">> docker not available: skipping image build and run"
  exit 0
fi

echo ">> 2/3 Build the image locally (not pushed anywhere)"
docker build -t azure-ci-cd-lab:local .

echo ">> 3/3 Run it and hit the endpoints"
cid="$(docker run -d --rm -p 8082:8080 -e APP_ENV=local -e APP_PLATFORM=laptop -e APP_VERSION=localtest azure-ci-cd-lab:local)"
trap 'docker stop "$cid" >/dev/null' EXIT
for i in $(seq 1 15); do curl -fs http://localhost:8082/healthz >/dev/null 2>&1 && break; sleep 1; done
curl -fsS http://localhost:8082/version
echo
echo "OK: the same image would be promoted through the pipeline."
