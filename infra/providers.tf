terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      # Prevents accidental deletion of non-empty resource groups
      prevent_deletion_if_contains_resources = true
    }
    cosmosdb_account {
      # Keeps the account if you accidentally remove it from Terraform state
      # Remove this in a real destroy scenario
    }
  }
}
