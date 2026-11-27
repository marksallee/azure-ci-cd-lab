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

VER="$(curl -fsSL https://api.github.com/repos/actions/runner/releases/latest | grep -m1 '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')"
mkdir -p "$RUNNER_DIR" && cd "$RUNNER_DIR"
curl -fsSL -o runner.tgz "https://github.com/actions/runner/releases/download/v${VER}/actions-runner-linux-${ARCH}-${VER}.tar.gz"
tar xzf runner.tgz && rm runner.tgz

./config.sh --unattended --url "https://github.com/${REPO}" --token "$TOKEN" \
  --labels homelab --name "$(hostname)-homelab" --replace
sudo ./svc.sh install "$USER"
sudo ./svc.sh start
echo "Runner installed. If you were just added to the docker group, run: sudo ./svc.sh stop && sudo ./svc.sh start"
echo "Then on your workstation: gh variable set ENABLE_HOMELAB --repo ${REPO} --body true"
