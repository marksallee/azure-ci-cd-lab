#!/usr/bin/env bash
# Run ON the non-Azure VM (Debian/Ubuntu, Docker already installed).
# Installs a GitHub Actions self-hosted runner as a systemd service.
#   usage: ./install-runner.sh <owner/repo> <registration-token>
# Get the token (valid ~1 hour) from your workstation:
#   gh api -X POST repos/<owner/repo>/actions/runners/registration-token --jq .token
set -euo pipefail

REPO="${1:?usage: $0 <owner/repo> <registration-token>}"
TOKEN="${2:?registration token required}"
RUNNER_DIR="$HOME/actions-runner"

command -v docker >/dev/null || { echo "Install Docker first (docker + compose plugin)"; exit 1; }
sudo usermod -aG docker "$USER" || true

case "$(uname -m)" in
  x86_64) ARCH=x64 ;;
  aarch64) ARCH=arm64 ;;
  *) echo "unsupported arch"; exit 1 ;;
esac

# Latest runner version. Override with RUNNER_VERSION=2.xxx.x if the API is unreachable.
# The response is saved to a file first: piping curl into `grep -m1` closes the
# pipe early and makes curl fail with exit code 23 under `set -o pipefail`.
VER="${RUNNER_VERSION:-}"
if [ -z "$VER" ]; then
  tmp="$(mktemp)"
  curl -fsSL https://api.github.com/repos/actions/runner/releases/latest -o "$tmp"
  VER="$(sed -n 's/.*"tag_name": *"v\([^"]*\)".*/\1/p' "$tmp" | head -n1)"
  rm -f "$tmp"
fi
[ -n "$VER" ] || { echo "could not determine the runner version; set RUNNER_VERSION"; exit 1; }
mkdir -p "$RUNNER_DIR" && cd "$RUNNER_DIR"
curl -fsSL -o runner.tgz "https://github.com/actions/runner/releases/download/v${VER}/actions-runner-linux-${ARCH}-${VER}.tar.gz"
tar xzf runner.tgz && rm runner.tgz

./config.sh --unattended --url "https://github.com/${REPO}" --token "$TOKEN" \
  --labels homelab --name "$(hostname)-homelab" --replace
sudo ./svc.sh install "$USER"
sudo ./svc.sh start
echo "Runner installed. If you were just added to the docker group, run: sudo ./svc.sh stop && sudo ./svc.sh start"
echo "Then on your workstation: gh variable set ENABLE_HOMELAB --repo ${REPO} --body true"
