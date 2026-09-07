terraform {
  required_version = "1.16.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "5.2.0"
    }
  }

  cloud {
    organization = "abe-terraform-lab"
    workspaces {
      name = "azure-storage-lab"
    }
  }
}

provider "azurerm" {
  # Configuration options
  features {}
}


