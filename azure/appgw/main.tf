terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "2.64.0"
    }
  }
}

variable "appgw_name" {
  type        = string
  description = "Application Gateway name"
}

variable "vnet_name" {
  type        = string
  description = "Virtual network name"
}

variable "resource_group_name" {
  type        = string
  description = "Resource Group name"
}

variable "location" {
  type        = string
  description = "Location"
}

variable "frontend_subnet_id" {
  type        = string
  description = "Subnet of frontend"
}

variable "backend_port" {
  type        = number
  description = "Backend port"
  default     = 80
}

variable "default_url_paths" {
  type        = list(string)
  description = "Default URL paths"
  default     = ["/noop"]
}

variable "http_listener_protocol" {
  type        = string
  description = "HTTP listener protocol"
  default     = "HTTP"
  validation {
    condition     = var.http_listener_protocol == "HTTP" || var.http_listener_protocol == "HTTPS"
    error_message = "The http_listener_protocol value must be \"HTTP\" or \"HTTPS\"."
  }
}

locals {
  frontend_port                  = var.http_listener_protocol == "HTTP" ? 80 : 443
  backend_address_pool_name      = "${var.vnet_name}-beap"
  frontend_port_name             = "${var.vnet_name}-feport"
  frontend_ip_configuration_name = "${var.vnet_name}-feip"
  http_setting_name              = "${var.vnet_name}-be-htst"
  listener_name                  = "${var.vnet_name}-httplstn"
  request_routing_rule_name      = "${var.vnet_name}-rqrt"
  redirect_configuration_name    = "${var.vnet_name}-rdrcfg"
  url_path_map_name              = "${var.vnet_name}-upm"
  path_rule_name                 = "${var.vnet_name}-pr"
}

resource "azurerm_public_ip" "simple_appgw" {
  name                = "${var.appgw_name}-pip"
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
}

resource "azurerm_application_gateway" "simple_http_appgw" {
  name                = var.appgw_name
  resource_group_name = var.resource_group_name
  location            = var.location

  sku {
    name     = "Standard_Small"
    tier     = "Standard"
    capacity = 1
  }

  gateway_ip_configuration {
    name      = "gateway-ip-configuration"
    subnet_id = var.frontend_subnet_id
  }

  frontend_port {
    name = local.frontend_port_name
    port = 80
  }

  frontend_ip_configuration {
    name                 = local.frontend_ip_configuration_name
    public_ip_address_id = azurerm_public_ip.example.id
  }

  backend_address_pool {
    name = local.backend_address_pool_name
  }

  backend_http_settings {
    name                  = local.http_setting_name
    cookie_based_affinity = "Disabled"
    port                  = var.backend_port
    protocol              = "Http"
    request_timeout       = 60
  }

  http_listener {
    name                           = local.listener_name
    frontend_ip_configuration_name = local.frontend_ip_configuration_name
    frontend_port_name             = local.frontend_port_name
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = local.request_routing_rule_name
    rule_type                  = "PathBasedRouting"
    http_listener_name         = local.listener_name
    backend_address_pool_name  = local.backend_address_pool_name
    backend_http_settings_name = local.http_setting_name
  }

  url_path_map {
    name                               = local.url_path_map_name
    default_backend_address_pool_name  = local.backend_address_pool_name
    default_backend_http_settings_name = local.backend_http_settings_name
    path_rule = {
      name  = local.path_rule_name
      paths = var.default_url_paths
    }
  }
}
