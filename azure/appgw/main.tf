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

variable "ssl_cert_pfx_path" {
  type        = string
  description = "Path of SSL certificate pfx"
  default     = ""
}

variable "ssl_cert_password" {
  type        = string
  description = "SSL certificate password"
  default     = ""
}

locals {
  ssl_resource_count                     = var.http_listener_protocol == "HTTPS" ? 1 : 0
  frontend_port                          = var.http_listener_protocol == "HTTPS" ? 443 : 80
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
  ssl_certificate_name                   = var.http_listener_protocol == "HTTPS" ? "${var.appgw_name}-ssl" : ""
}

resource "azurerm_user_assigned_identity" "simple_appgw" {
  count               = local.ssl_resource_count
  resource_group_name = var.resource_group_name
  location            = var.location
  name                = "${var.appgw_name}-id"
}

resource "azurerm_key_vault" "simple_appgw_ssl" {
  count                       = local.ssl_resource_count
  name                        = "${var.appgw_name}-ssl-certificate"
  location                    = var.location
  resource_group_name         = var.resource_group_name
  enabled_for_disk_encryption = true
  tenant_id                   = azurerm_user_assigned_identity.simple_appgw.0.tenant_id
  soft_delete_retention_days  = 7
  purge_protection_enabled    = false

  sku_name = "standard"

  access_policy {
    tenant_id      = azurerm_user_assigned_identity.simple_appgw.0.tenant_id
    object_id      = azurerm_user_assigned_identity.simple_appgw.0.principal_id
    application_id = azurerm_user_assigned_identity.simple_appgw.0.client_id

    certificate_permissions = [
      "Get",
    ]

  }

  network_acls {
    bypass                     = "AzureServices"
    default_action             = "Allow"
    virtual_network_subnet_ids = [var.frontend_subnet_id]
  }
}

resource "azurerm_key_vault_certificate" "simple_appgw_ssl_certificate" {
  count        = local.ssl_resource_count
  name         = "${var.appgw_name}-ssl-cert"
  key_vault_id = azurerm_key_vault.simple_appgw_ssl.0.id

  certificate {
    contents = filebase64(var.ssl_cert_pfx_path)
    password = var.ssl_cert_password
  }

  certificate_policy {
    issuer_parameters {
      name = "Unknown"
    }

    key_properties {
      curve      = "P-384"
      exportable = true
      key_size   = 384
      key_type   = "EC"
      reuse_key  = false
    }

    lifetime_action {
      action {
        action_type = "AutoRenew"
      }
      trigger {
        days_before_expiry = 30
      }
    }

    secret_properties {
      content_type = "application/x-pkcs12"
    }
  }
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
    ssl_certificate_name           = local.ssl_certificate_name
  }

  dynamic "ssl_certificate" {
    for_each = local.ssl_resource_count == 1 ? [1] : []
    content {
      name                = local.ssl_certificate_name
      key_vault_secret_id = azurerm_key_vault_certificate.simple_appgw_ssl_certificate.0.id
    }
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
