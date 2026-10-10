terraform {
  required_version = "1.16.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "5.2.0"
    }
  }

  backend "azurerm" {
    resource_group_name  = "rg-tfstate"
    storage_account_name = "stabestfstate001"
    container_name       = "tfstate001"
    key                  = "storage/terraform.tfstate"
    use_azuread_auth = true
  }
}

provider "azurerm" {
  # Configuration options
  features {}
}


