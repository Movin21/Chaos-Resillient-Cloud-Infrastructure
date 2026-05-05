output "app_name" {
  value = azurerm_linux_web_app.main.name
}

output "default_hostname" {
  description = "The public URL assigned by Azure (before Front Door is attached)"
  value       = azurerm_linux_web_app.main.default_hostname
}

output "app_id" {
  description = "Resource ID — needed by Front Door to register this as an origin"
  value       = azurerm_linux_web_app.main.id
}

output "outbound_ip_addresses" {
  description = "IPs this app uses for outbound calls — useful for firewall rules"
  value       = azurerm_linux_web_app.main.outbound_ip_addresses
}
