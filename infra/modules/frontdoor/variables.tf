variable "project_name" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "primary_app_hostname" {
  description = "default_hostname of the West Europe Web App (no https://)"
  type        = string
}

variable "secondary_app_hostname" {
  description = "default_hostname of the East US Web App (no https://)"
  type        = string
}

variable "primary_app_name" {
  description = "Resource name of the West Europe Web App — used for tagging"
  type        = string
}

variable "secondary_app_name" {
  description = "Resource name of the East US Web App — used for tagging"
  type        = string
}
