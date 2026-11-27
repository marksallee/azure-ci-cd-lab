resource "proxmox_virtual_environment_container" "runner" {
  node_name     = var.node_name
  vm_id         = var.vm_id
  description   = "Managed by Terraform: GitHub Actions self-hosted runner (azure-ci-cd-lab)"
  unprivileged  = true
  start_on_boot = true
  started       = true

  # Docker in an unprivileged container needs nesting AND keyctl. Proxmox only
  # lets root@pam set feature flags other than nesting (API tokens cannot, even
  # root's), so keyctl is added once by hand after creation:
  #   pct set <vm_id> --features nesting=1,keyctl=1
  # lifecycle.ignore_changes below stops Terraform from trying to revert it.
  features {
    nesting = true
  }

  cpu {
    cores = var.cores
  }

  memory {
    dedicated = var.memory_mb
    swap      = var.swap_mb
  }

  disk {
    datastore_id = var.datastore_id
    size         = var.disk_gb
  }

  network_interface {
    name   = "eth0"
    bridge = var.bridge
  }

  operating_system {
    template_file_id = var.template_file_id
    type             = "ubuntu"
  }

  initialization {
    hostname = var.hostname

    ip_config {
      ipv4 {
        address = var.address
        gateway = var.gateway
      }
    }

    dns {
      servers = var.dns_servers
    }

    user_account {
      keys = var.ssh_public_keys
    }
  }

  lifecycle {
    # The template and keys only matter at creation; changing them must not
    # rebuild a running runner.
    ignore_changes = [operating_system, initialization[0].user_account, features]
  }
}
