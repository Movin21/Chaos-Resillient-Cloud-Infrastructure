output "endpoint" {
  description = "The primary Cosmos DB endpoint URL"
  value       = azurerm_cosmosdb_account.main.endpoint
}

output "primary_key" {
  description = "The primary read-write key (treat as a secret)"
  value       = azurerm_cosmosdb_account.main.primary_key
  sensitive   = true
}

output "account_name" {
  value = azurerm_cosmosdb_account.main.name
}

output "connection_strings" {
  description = "All connection strings for the account"
  value       = azurerm_cosmosdb_account.main.connection_strings
  sensitive   = true
}
