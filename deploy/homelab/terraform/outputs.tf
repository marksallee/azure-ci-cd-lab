output "runner_address" {
  description = "IPv4 address of the runner container"
  value       = var.address
}

output "ssh_hint" {
  description = "How to reach the container"
  value       = "ssh root@${split("/", var.address)[0]}"
}
