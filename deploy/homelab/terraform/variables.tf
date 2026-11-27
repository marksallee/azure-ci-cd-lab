variable "proxmox_endpoint" {
  type        = string
  description = "Proxmox API URL, for example https://<host>:8006/"
}

variable "proxmox_insecure" {
  type        = bool
  default     = true
  description = "Skip TLS verification (self-signed certificate)"
}

variable "node_name" {
  type        = string
  description = "Proxmox node name that hosts the container (shown under Datacenter in the web UI, or run `hostname` on the host). A wrong name fails with 'hostname lookup failed'."
}

variable "vm_id" {
  type        = number
  description = "Unused container ID"
}

variable "hostname" {
  type    = string
  default = "gh-runner"
}

variable "datastore_id" {
  type        = string
  default     = "local-lvm"
  description = "Storage for the container disk"
}

variable "template_file_id" {
  type        = string
  default     = "local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
  description = "LXC template, already downloaded with pveam"
}

variable "bridge" {
  type    = string
  default = "vmbr0"
}

variable "address" {
  type        = string
  description = "Container IPv4 in CIDR form, for example 192.168.1.50/24. Verify it is free first."
}

variable "gateway" {
  type        = string
  description = "Default gateway"
}

variable "dns_servers" {
  type        = list(string)
  description = "DNS servers for the container"
}

variable "ssh_public_keys" {
  type        = list(string)
  description = "Public keys allowed to log in as root on the container"
}

variable "cores" {
  type    = number
  default = 2
}

variable "memory_mb" {
  type    = number
  default = 2048
}

variable "swap_mb" {
  type    = number
  default = 512
}

variable "disk_gb" {
  type    = number
  default = 20
}
