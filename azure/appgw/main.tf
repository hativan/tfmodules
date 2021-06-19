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

variable "domain_name_label" {
  type        = string
  description = "Domain name of Application Gateway"
}

variable "appgw_private_ip_address" {
  type        = string
  description = "Application Gateway private ip addresss"
}

variable "dns_a_record_name" {
  type        = string
  description = "Application Gateway domain name"
  default     = ""
}

variable "dns_zone" {
  type        = string
  description = "Application Gateway domain zone"
  default     = ""
}

locals {
  frontend_port                          = var.http_listener_protocol == "HTTP" ? 80 : 443
  backend_address_pool_name              = "${var.vnet_name}-beap"
  backend_http_settings_name             = "${var.vnet_name}-behs"
  frontend_port_name                     = "${var.vnet_name}-feport"
  frontend_public_ip_configuration_name  = "${var.vnet_name}-fepubip"
  frontend_private_ip_configuration_name = "${var.vnet_name}-feprivip"
  listener_name                          = "${var.vnet_name}-httplstn"
  request_routing_rule_name              = "${var.vnet_name}-rqrt"
  redirect_configuration_name            = "${var.vnet_name}-rdrcfg"
  url_path_map_name                      = "${var.vnet_name}-upm"
  path_rule_name                         = "${var.vnet_name}-pr"
}

resource "azurerm_public_ip" "simple_appgw" {
  name                = "${var.appgw_name}-pip"
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Dynamic"
  sku                 = "Basic"
  domain_name_label   = var.domain_name_label
}

resource "azurerm_network_security_group" "simple_appgw_frontend" {
  name                = "${var.appgw_name}-frontend-nsg"
  location            = var.location
  resource_group_name = var.resource_group_name

  security_rule {
    name                       = "inbound-http"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = local.frontend_port
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "simple_appgw_frontend" {
  subnet_id                 = var.frontend_subnet_id
  network_security_group_id = azurerm_network_security_group.simple_appgw_frontend.id
}

resource "azurerm_application_gateway" "simple_appgw" {
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
    name                 = local.frontend_public_ip_configuration_name
    public_ip_address_id = azurerm_public_ip.simple_appgw.id
  }

  frontend_ip_configuration {
    name                          = local.frontend_private_ip_configuration_name
    subnet_id                     = var.frontend_subnet_id
    private_ip_address            = var.appgw_private_ip_address
    private_ip_address_allocation = "Static"
  }

  backend_address_pool {
    name = local.backend_address_pool_name
  }

  backend_http_settings {
    name                  = local.backend_http_settings_name
    cookie_based_affinity = "Disabled"
    port                  = var.backend_port
    protocol              = "Http"
    request_timeout       = 60
  }

  http_listener {
    name                           = local.listener_name
    frontend_ip_configuration_name = local.frontend_public_ip_configuration_name
    frontend_port_name             = local.frontend_port_name
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = local.request_routing_rule_name
    rule_type                  = "PathBasedRouting"
    http_listener_name         = local.listener_name
    backend_address_pool_name  = local.backend_address_pool_name
    backend_http_settings_name = local.backend_http_settings_name
    url_path_map_name          = local.url_path_map_name
  }

  url_path_map {
    name                               = local.url_path_map_name
    default_backend_address_pool_name  = local.backend_address_pool_name
    default_backend_http_settings_name = local.backend_http_settings_name
    path_rule {
      name                       = local.path_rule_name
      paths                      = var.default_url_paths
      backend_address_pool_name  = local.backend_address_pool_name
      backend_http_settings_name = local.backend_http_settings_name
    }
  }

  timeouts {
    create = "60m"
    delete = "60m"
  }
}

resource "azurerm_dns_a_record" "simple_appgw" {
  depends_on = [
    azurerm_application_gateway.simple_appgw
  ]
  count               = var.dns_a_record_name != "" && var.dns_zone != "" ? 1 : 0
  name                = var.dns_a_record_name
  zone_name           = var.dns_zone
  resource_group_name = var.resource_group_name
  ttl                 = 300
  target_resource_id  = azurerm_public_ip.simple_appgw.id
}
