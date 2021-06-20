terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "2.64.0"
    }
  }
}

variable "subscription_id" {
  type        = string
  description = "Azure subscription id"
}

variable "tenant_id" {
  type        = string
  description = "Azure tenant id"
}

provider "azurerm" {
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
  features {
    key_vault {
      purge_soft_delete_on_destroy = true
    }
  }
}

resource "azurerm_resource_group" "example" {
  name     = "example"
  location = "eastus"
}

locals {
  resource_group_name = azurerm_resource_group.example.name
  location            = azurerm_resource_group.example.location
}

module "vnet" {
  source              = "./azure/vnet"
  vnet_name           = "example-vnet"
  location            = local.location
  resource_group_name = local.resource_group_name
  vnet_address_space  = ["10.0.0.0/16"]
}

module "subnet" {
  source = "./azure/subnet"
  subnets = {
    frontend = {
      name              = "appgw-frontend"
      address_prefixes  = ["10.0.1.0/24"]
      service_endpoints = ["Microsoft.KeyVault"]
    }
    backend = {
      name              = "appgw-backend"
      address_prefixes  = ["10.0.2.0/24"]
      service_endpoints = ["Microsoft.Storage"]
    }
  }
  resource_group_name = local.resource_group_name
  vnet_name           = module.vnet.vnet_name
}

module "appgw" {
  source              = "./azure/appgw"
  appgw_name          = "example-appgw"
  vnet_name           = module.vnet.vnet_name
  resource_group_name = local.resource_group_name
  location            = local.location
  frontend_subnet_id  = module.subnet.subnet_ids.appgw_frontend
  domain_name_label   = "example-appgw"
}
