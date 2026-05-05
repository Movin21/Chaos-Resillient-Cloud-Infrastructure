variable "project_name" {
  description = "Short name used as a prefix for all resources"
  type        = string
  default     = "chaosinfra"
}

variable "primary_region" {
  description = "Primary Azure region (e.g. West Europe)"
  type        = string
  default     = "West Europe"
}

variable "secondary_region" {
  description = "Failover Azure region (e.g. East US)"
  type        = string
  default     = "East US"
}

variable "environment" {
  description = "Deployment environment tag"
  type        = string
  default     = "dev"
}
