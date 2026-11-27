# Self-hosted runner on a Proxmox LXC container

The non-Azure target is an unprivileged LXC container on Proxmox that runs a
GitHub Actions runner and Docker. The runner opens an outbound HTTPS connection
to GitHub, so nothing needs to reach into the home network.

Why LXC and not a VM: if the Proxmox host is itself virtualized (for example
inside VirtualBox), VMs need nested KVM, which can be unstable under load.
Unprivileged containers share the host kernel, use less memory, and run Docker
fine with `nesting=1,keyctl=1`.

Use a **dedicated container** for this runner. Do not reuse a container that
holds other CI runners or deploy keys: a self-hosted runner executes workflow
code, so it should hold no secrets and have no trust relationship with anything
else on the network.

Placeholders: `<CTID>` an unused container ID, `<IP>/<MASK>` and `<GATEWAY>` a
verified-free address, `<STORAGE>` your container storage, `<OWNER>/<REPO>` the
GitHub repository.

## 1. Create the container (on the Proxmox host)

Check the address is free first, and outside the router's DHCP pool:
```bash
ping -c1 -W1 <IP> >/dev/null && echo "IN USE" || echo "free"
pvesm status                       # storage names
pveam list local                   # confirm the Ubuntu 24.04 template is present
```
### Option A: Terraform (recommended)

The configuration is in [terraform/](terraform/). It uses the `bpg/proxmox`
provider and an API token from the environment, so no secret is stored in files.
```bash
cd deploy/homelab/terraform
cp terraform.tfvars.example terraform.tfvars      # edit: endpoint, vm_id, address, gateway, DNS, SSH key
export PROXMOX_VE_API_TOKEN='<user>@<realm>!<token-name>=<secret>'
terraform init
terraform plan                                    # expect exactly one container to add
terraform apply
```
Review the plan before applying: it should create one container and nothing else.
`terraform destroy` removes it. State stays local and is git-ignored.

**One manual step.** Proxmox only lets `root@pam` set container feature flags
other than `nesting`, and API tokens cannot (even a token owned by root). So
Terraform creates the container with `nesting` and you add `keyctl` once, as
root on the Proxmox host. Docker in an unprivileged container needs it:
```bash
pct set <CTID> --features nesting=1,keyctl=1
pct reboot <CTID>
```
Terraform ignores the feature flags afterwards, so later plans stay clean.

**API token permissions.** If you create the token with Privilege Separation on,
grant it roles explicitly (adjust the token ID and paths to your setup):
```bash
pveum acl modify /vms --tokens '<user>@<realm>!<token-id>' --roles PVEVMAdmin
pveum acl modify /storage --tokens '<user>@<realm>!<token-id>' --roles PVEDatastoreUser
pveum acl modify /sdn/zones/localnetwork --tokens '<user>@<realm>!<token-id>' --roles PVESDNUser
```

### Option B: `pct` commands

Create and start it:
```bash
pct create <CTID> local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst \
  --hostname gh-runner --cores 2 --memory 2048 --swap 512 \
  --rootfs <STORAGE>:20 --unprivileged 1 --features nesting=1,keyctl=1 \
  --net0 name=eth0,bridge=vmbr0,ip=<IP>/<MASK>,gw=<GATEWAY> \
  --nameserver <GATEWAY> --ssh-public-keys ~/.ssh/authorized_keys --onboot 1
pct start <CTID>
```
## 2. Prepare the container

SSH in as root and run the helper script (copy `deploy/homelab/bootstrap-container.sh`
to the container first). It installs Docker, creates the `ghrunner` user and a
temporary sudo rule, and is safe to re-run:
```bash
./bootstrap-container.sh
```
The manual equivalent, if you prefer to see each step:
```bash
apt update && apt install -y sudo curl
curl -fsSL https://get.docker.com | sh
docker run --rm hello-world
# The runner refuses to run as root, so create a normal user for it
adduser --disabled-password --gecos "" ghrunner
usermod -aG docker,sudo ghrunner
echo "ghrunner ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ghrunner   # needed once by svc.sh; remove afterwards
mkdir -p /home/ghrunner/.ssh && cp ~/.ssh/authorized_keys /home/ghrunner/.ssh/
chown -R ghrunner:ghrunner /home/ghrunner/.ssh
```
Copy `deploy/homelab/install-runner.sh` to the container (or clone the repo there).

## 3. Register the runner

On your workstation, get a registration token (valid about one hour, treat it as
a secret and never paste it into chat or commit it):
```bash
gh api -X POST repos/<OWNER>/<REPO>/actions/runners/registration-token --jq .token
```
On the container, as `ghrunner`:
```bash
./install-runner.sh <OWNER>/<REPO> <TOKEN>
```
Then remove the temporary sudo rule as root:
```bash
rm /etc/sudoers.d/ghrunner
```
Check it from your workstation:
```bash
gh api repos/<OWNER>/<REPO>/actions/runners \
  --jq '.runners[] | {name, status, labels: [.labels[].name]}'
```
Expect `status: online` and the label `homelab`.

## 4. Lock it down, then enable the job

1. Repository → Settings → Actions → General → **Require approval for all outside collaborators**.
2. Create the `homelab` environment restricted to `main` (the Azure setup script does this too):
   ```bash
   gh api --method PUT repos/<OWNER>/<REPO>/environments/homelab \
     --input - <<< '{"deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true}}'
   gh api --method POST repos/<OWNER>/<REPO>/environments/homelab/deployment-branches -f name=main
   ```
3. Enable the stage:
   ```bash
   gh variable set ENABLE_HOMELAB --repo <OWNER>/<REPO> --body true
   ```

## 5. Run and verify

Push to `main`, or run `gh workflow run cd.yml --ref main`. With `ENABLE_AZURE`
unset, the Azure stages are skipped and the `homelab` job runs on its own.
```bash
curl http://<IP>:8081/version
```
The JSON should show `"platform": "self-hosted-vm"` and the commit SHA of the run.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `config.sh` says it must not run as root | Ran as root | Run as the `ghrunner` user |
| Job queued, never starts | Runner offline or wrong label | Check `systemctl status` of the runner service and the `homelab` label |
| `permission denied` on the Docker socket | User not in the `docker` group yet | Re-login, or restart the runner service (`sudo ./svc.sh stop && sudo ./svc.sh start`) |
| `apt update`: "Release file ... is not valid yet" | The Proxmox host clock is wrong (containers use the host's clock; common when Proxmox runs in a VM that was paused) | On the host: `date -u -s '<current UTC time>'`, `hwclock --systohc`, `chronyc makestep`, then `chronyc tracking` to confirm. Set `makestep 1 -1` in `/etc/chrony/chrony.conf` so large errors self-correct |
| Terraform: 403 `Permission check failed` with no detail | The API token has Privilege Separation on and no ACLs | Grant roles to the token (see above) or recreate it without separation |
| Terraform: 403 `changing feature flags (except nesting) is only allowed for root@pam` | Tokens cannot set `keyctl` | Create with `nesting` only, then `pct set <CTID> --features nesting=1,keyctl=1` as root |
| Terraform: `hostname lookup '<name>' failed` (HTTP 500) | `node_name` isn't the real Proxmox node name | Use the name shown under Datacenter in the UI (or `hostname` on the host) |
| Intermittent SSH or network failures | Duplicate IP on the LAN | Check ARP and pick another verified-free address |
| `Could not resolve host` | DNS not set on the container | Set `--nameserver` on the container |

## Cleanup

```bash
# on the container, as ghrunner
cd ~/actions-runner && sudo ./svc.sh stop && sudo ./svc.sh uninstall
./config.sh remove --token <NEW_REMOVAL_TOKEN>
# on the Proxmox host
pct stop <CTID> && pct destroy <CTID> --purge
```
