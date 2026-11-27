terraform {
  required_version = ">= 1.6"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }

  # Partial config: the workflow supplies storage account / key per environment
  # via -backend-config, so the same code serves dev, staging and prod.
  backend "azurerm" {}
}

provider "azurerm" {
  features {}
  # bootstrap-azure.sh registers the resource providers once with owner rights.
  # The CI identity only has Contributor on its resource group, so it must not
  # try to register providers itself.
  resource_provider_registrations = "none"
  # Auth comes from ARM_USE_OIDC / ARM_CLIENT_ID / ARM_TENANT_ID / ARM_SUBSCRIPTION_ID
  # (set by the workflow) - no client secret anywhere.
}
