terraform {
  required_version = "~> 1.16.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "5.2.0"
    }
  }

  cloud {
    organization = "abe-terraform-lab"
    workspaces {
      name = "azure-aks-lab"
    }
  }
}

provider "azurerm" {
  # Configuration options
  features {}
}

resource "azurerm_resource_group" "rg" {
  name     = "lab-aks-rg"
  location = "eastus"
}

resource "azurerm_kubernetes_cluster" "aks" { 
  name                = "lab-aks1"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = "labaks1"

  node_provisioning_profile {
    mode = "Manual"
  }
  default_node_pool {
    name                 = "default"
    node_count           = 1
    vm_size              = "Standard_D2ads_v7"
    auto_scaling_enabled = true
    min_count            = 1
    max_count            = 2
  }

  identity {
    type = "SystemAssigned"
  }

  sku_tier = "Free"

  tags = {
    Environment = "Dev"
  }
}