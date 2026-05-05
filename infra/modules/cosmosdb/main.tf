resource "azurerm_cosmosdb_account" "main" {
  name                = "${var.project_name}-cosmos-${var.environment}"
  location            = var.primary_region
  resource_group_name = var.resource_group_name
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"

  # --- THE HEART OF CHAOS RESILIENCE ---
  # enable_multiple_write_locations = true means BOTH regions accept writes
  # simultaneously. There is no "primary master" that can become a single
  # point of failure. If West Europe disappears, East US never stops writing.
  enable_multiple_write_locations = true

  # Automatic failover is a fallback for when multi-write isn't enough
  # (e.g., the Cosmos control plane itself has an issue in one region).
  enable_automatic_failover = true

  consistency_policy {
    # BoundedStaleness: reads may lag writes by at most `interval_in_seconds`.
    # This is the recommended balance for multi-write: strong enough for most
    # apps, yet doesn't block writes waiting for global consensus.
    consistency_level       = "BoundedStaleness"
    max_interval_in_seconds = 300   # reads can be at most 5 minutes stale
    max_staleness_prefix    = 100000
  }

  # Primary region — set failover_priority = 0 to designate it "first choice"
  geo_location {
    location          = var.primary_region
    failover_priority = 0
  }

  # Secondary region — priority 1 means "use this if priority 0 is unhealthy"
  geo_location {
    location          = var.secondary_region
    failover_priority = 1
  }

  tags = {
    environment = var.environment
    project     = var.project_name
    managed_by  = "terraform"
  }
}

# A database inside the account
resource "azurerm_cosmosdb_sql_database" "main" {
  name                = "appdb"
  resource_group_name = var.resource_group_name
  account_name        = azurerm_cosmosdb_account.main.name
}

# A container (like a table) inside the database
resource "azurerm_cosmosdb_sql_container" "events" {
  name                = "events"
  resource_group_name = var.resource_group_name
  account_name        = azurerm_cosmosdb_account.main.name
  database_name       = azurerm_cosmosdb_sql_database.main.name
  partition_key_path  = "/regionOrigin"  # partition by which region wrote the record

  throughput = 400  # minimum RU/s — increase for production
}
