terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "2.64.0"
    }
  }
}

variable "vnet_name" {
  type        = string
  description = "Virtual Network name"
}

variable "location" {
  type        = string
  description = "Virtula Network location"
  default     = "eastus"
}

variable "resource_group_name" {
  type        = string
  description = "Resource Group name"
}

variable "vnet_address_space" {
  type        = list(string)
  description = "Virtual Network address space"
  validation {
    condition = can(
      [
        for s in var.vnet_address_space : regex(
          "^\\d{1,3}?\\.\\d{1,3}?\\.\\d{1,3}?\\.\\d{1,3}?/\\d{1,2}?", s
        )
      ]
    )
    error_message = "The address space must be format of CIDR."
  }
}

resource "azurerm_virtual_network" "simple_vnet" {
  name                = var.vnet_name
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = var.vnet_address_space
}

output "vnet_name" {
  value = azurerm_virtual_network.simple_vnet.name
}
