#!/usr/bin/env bash
# Run ON the new Proxmox container, as root (SSH in as root once).
# Installs Docker and creates the non-root user the GitHub runner needs.
# Safe to re-run.
#   usage: ./bootstrap-container.sh [runner-user]
set -euo pipefail

RUNNER_USER="${1:-ghrunner}"
[ "$(id -u)" -eq 0 ] || { echo "run as root"; exit 1; }

apt-get update
apt-get install -y sudo curl ca-certificates

if ! command -v docker >/dev/null; then
  curl -fsSL https://get.docker.com | sh
fi
docker run --rm hello-world >/dev/null && echo "docker OK"

id "$RUNNER_USER" >/dev/null 2>&1 || adduser --disabled-password --gecos "" "$RUNNER_USER"
usermod -aG docker,sudo "$RUNNER_USER"

# The runner's svc.sh needs sudo once. Remove this file after install-runner.sh succeeds.
echo "$RUNNER_USER ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$RUNNER_USER"
chmod 440 "/etc/sudoers.d/$RUNNER_USER"

install -d -m 700 -o "$RUNNER_USER" -g "$RUNNER_USER" "/home/$RUNNER_USER/.ssh"
if [ -f /root/.ssh/authorized_keys ]; then
  install -m 600 -o "$RUNNER_USER" -g "$RUNNER_USER" /root/.ssh/authorized_keys "/home/$RUNNER_USER/.ssh/authorized_keys"
fi

echo "Done. Next, as $RUNNER_USER: ./install-runner.sh <owner/repo> <token>"
echo "Afterwards, as root: rm /etc/sudoers.d/$RUNNER_USER"
