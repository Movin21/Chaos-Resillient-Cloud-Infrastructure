output "endpoint_hostname" {
  description = "The public .azurefd.net URL — this is what your users hit"
  value       = azurerm_cdn_frontdoor_endpoint.main.host_name
}

output "profile_id" {
  value = azurerm_cdn_frontdoor_profile.main.id
}

output "origin_group_id" {
  value = azurerm_cdn_frontdoor_origin_group.main.id
}
