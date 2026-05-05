resource "azurerm_resource_group" "main" {
  name     = "${var.project_name}-rg-${var.environment}"
  location = var.primary_region

  tags = {
    environment = var.environment
    project     = var.project_name
  }
}

module "cosmosdb" {
  source = "./modules/cosmosdb"

  project_name        = var.project_name
  primary_region      = var.primary_region
  secondary_region    = var.secondary_region
  resource_group_name = azurerm_resource_group.main.name
  environment         = var.environment
}

# Primary region Web App — West Europe
module "webapp_primary" {
  source = "./modules/webapp"

  project_name         = var.project_name
  region               = var.primary_region
  region_short         = "weu"
  resource_group_name  = azurerm_resource_group.main.name
  environment          = var.environment
  cosmos_endpoint      = module.cosmosdb.endpoint
  cosmos_primary_key   = module.cosmosdb.primary_key
}

# Secondary region Web App — East US
# Identical config, different region. Both are active — this is Active-Active,
# not Active-Passive. Front Door splits traffic between them until one fails.
module "webapp_secondary" {
  source = "./modules/webapp"

  project_name         = var.project_name
  region               = var.secondary_region
  region_short         = "eus"
  resource_group_name  = azurerm_resource_group.main.name
  environment          = var.environment
  cosmos_endpoint      = module.cosmosdb.endpoint
  cosmos_primary_key   = module.cosmosdb.primary_key
}

# Azure Front Door — single global entry point over both Web Apps
module "frontdoor" {
  source = "./modules/frontdoor"

  project_name           = var.project_name
  resource_group_name    = azurerm_resource_group.main.name
  environment            = var.environment
  primary_app_hostname   = module.webapp_primary.default_hostname
  secondary_app_hostname = module.webapp_secondary.default_hostname
  primary_app_name       = module.webapp_primary.app_name
  secondary_app_name     = module.webapp_secondary.app_name
}
