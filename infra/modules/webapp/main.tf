# App Service Plan = the VM underneath your Web App.
# You pay for the Plan, not the App itself.
# We create one Plan per region so the two regions are fully independent —
# a regional Azure outage that kills the Plan in West Europe cannot touch
# the Plan running in East US.
resource "azurerm_service_plan" "main" {
  name                = "${var.project_name}-plan-${var.region_short}-${var.environment}"
  location            = var.region
  resource_group_name = var.resource_group_name
  os_type             = "Linux"

  # B1 = Basic tier, 1 core, 1.75 GB RAM.
  # Enough for a demo; swap to P1v3 for production.
  sku_name = "B1"

  tags = {
    environment = var.environment
    project     = var.project_name
    region      = var.region
  }
}

resource "azurerm_linux_web_app" "main" {
  name                = "${var.project_name}-app-${var.region_short}-${var.environment}"
  location            = var.region
  resource_group_name = var.resource_group_name
  service_plan_id     = azurerm_service_plan.main.id

  # HTTPS-only forces the browser redirect; no plain-HTTP traffic
  https_only = true

  site_config {
    always_on = true  # keeps the process warm; prevents cold-start latency

    application_stack {
      # A lightweight Node.js container — swap for python, dotnet, etc.
      node_version = "20-lts"
    }

    # Health check path: Azure Front Door probes this URL.
    # If it returns non-2xx, Front Door marks this origin unhealthy
    # and stops sending traffic here — this is the automatic failover trigger.
    health_check_path = "/health"
  }

  app_settings = {
    # Tell the app which region it's running in — useful for logging and
    # for setting the Cosmos DB preferred write region.
    "REGION"                  = var.region
    "REGION_SHORT"            = var.region_short

    # Cosmos DB connection details passed in from the cosmosdb module output.
    # Stored as encrypted App Settings — never hard-coded in source.
    "COSMOS_ENDPOINT"         = var.cosmos_endpoint
    "COSMOS_DATABASE"         = var.cosmos_database_name

    # WEBSITE_RUN_FROM_PACKAGE = 1 tells Azure to run the app directly from
    # a zip package — faster deploys and an immutable runtime environment.
    "WEBSITE_RUN_FROM_PACKAGE" = "1"
  }

  # Cosmos key is a secret — mark it sensitive so it won't print in logs
  # Azure encrypts App Settings at rest automatically.
  app_settings_sensitive = {
    "COSMOS_KEY" = var.cosmos_primary_key
  }

  tags = {
    environment = var.environment
    project     = var.project_name
    region      = var.region
  }
}
