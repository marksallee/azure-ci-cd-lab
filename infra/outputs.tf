output "url" {
  value = "https://${azurerm_container_app.app.ingress[0].fqdn}"
}

output "resource_group" {
  value = data.azurerm_resource_group.rg.name
}
