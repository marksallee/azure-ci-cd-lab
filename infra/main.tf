locals {
  suffix = "${var.app_name}-${var.environment}"
  tags = {
    app         = var.app_name
    environment = var.environment
    managed_by  = "terraform"
    purpose     = "learning-lab"
  }
}

# The resource group is created by scripts/bootstrap-azure.sh (one per
# environment) so the CI identity only needs Contributor on that group, not on
# the whole subscription. Terraform manages everything inside it.
data "azurerm_resource_group" "rg" {
  name = "rg-${local.suffix}"
}

resource "azurerm_log_analytics_workspace" "logs" {
  name                = "log-${local.suffix}"
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  daily_quota_gb      = var.log_daily_quota_gb
  tags                = local.tags
}

resource "azurerm_container_app_environment" "env" {
  name                       = "cae-${local.suffix}"
  location                   = data.azurerm_resource_group.rg.location
  resource_group_name        = data.azurerm_resource_group.rg.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.logs.id
  tags                       = local.tags
}

resource "azurerm_container_app" "app" {
  name                         = "ca-${local.suffix}"
  container_app_environment_id = azurerm_container_app_environment.env.id
  resource_group_name          = data.azurerm_resource_group.rg.name
  revision_mode                = "Single"
  tags                         = local.tags

  template {
    min_replicas = var.min_replicas
    max_replicas = var.max_replicas

    container {
      name   = "app"
      image  = var.image
      cpu    = 0.25
      memory = "0.5Gi"

      env {
        name  = "APP_ENV"
        value = var.environment
      }
      env {
        name  = "APP_PLATFORM"
        value = "azure-container-apps"
      }
      env {
        name  = "APP_VERSION"
        value = var.app_version
      }

      liveness_probe {
        transport = "HTTP"
        path      = "/healthz"
        port      = 8080
      }
    }
  }

  ingress {
    external_enabled = true
    target_port      = 8080
    transport        = "auto"

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }
}
