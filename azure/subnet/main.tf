terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "2.64.0"
    }
  }
}

variable "subnets" {
  type = map(object({
    name              = string
    address_prefixes  = list(string)
    service_endpoints = list(string)
  }))
  description = "Subnet parameters"
}

variable "resource_group_name" {
  type        = string
  description = "Resource Group name"
}

variable "vnet_name" {
  type        = string
  description = "Virtual Network name"
}

resource "azurerm_subnet" "simple_subnet" {
  for_each             = var.subnets
  name                 = each.value.name
  resource_group_name  = var.resource_group_name
  virtual_network_name = var.vnet_name
  address_prefixes     = each.value.address_prefixes

  service_endpoints = each.value.service_endpoints
}

output "subnet_ids" {
  value = {
    for k, v in azurerm_subnet.simple_subnet : replace(v.name, "-", "_") => v.id
  }
  description = "Pair map of subnet name and id"
}
