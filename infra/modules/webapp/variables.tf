variable "project_name" {
  type = string
}

variable "region" {
  description = "Azure region where this Web App instance lives"
  type        = string
}

variable "region_short" {
  description = "Short label used in resource names, e.g. 'weu' or 'eus'"
  type        = string
}

variable "resource_group_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "cosmos_endpoint" {
  description = "Cosmos DB endpoint injected as an app setting"
  type        = string
}

variable "cosmos_primary_key" {
  description = "Cosmos DB primary key injected as a secret app setting"
  type        = string
  sensitive   = true
}

variable "cosmos_database_name" {
  description = "Name of the Cosmos DB SQL database"
  type        = string
  default     = "appdb"
}
