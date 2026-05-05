output "cosmos_endpoint" {
  description = "Cosmos DB endpoint — paste this into your app config"
  value       = module.cosmosdb.endpoint
}

output "cosmos_account_name" {
  value = module.cosmosdb.account_name
}

# Marked sensitive so it won't appear in plan output
output "cosmos_primary_key" {
  value     = module.cosmosdb.primary_key
  sensitive = true
}

output "webapp_primary_url" {
  description = "West Europe Web App direct URL (bypasses Front Door)"
  value       = "https://${module.webapp_primary.default_hostname}"
}

output "webapp_secondary_url" {
  description = "East US Web App direct URL (bypasses Front Door)"
  value       = "https://${module.webapp_secondary.default_hostname}"
}

output "webapp_primary_name" {
  value = module.webapp_primary.app_name
}

output "webapp_secondary_name" {
  value = module.webapp_secondary.app_name
}

output "frontdoor_url" {
  description = "The single global URL your users should bookmark — traffic auto-fails over"
  value       = "https://${module.frontdoor.endpoint_hostname}"
}

output "frontdoor_hostname" {
  description = "Raw hostname for DNS/CNAME configuration"
  value       = module.frontdoor.endpoint_hostname
}
