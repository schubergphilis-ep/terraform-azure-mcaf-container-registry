resource "azurerm_resource_group" "this" {
  count = var.resource_group_name == null ? 0 : 1

  name     = var.resource_group_name
  location = var.location
}

resource "azurerm_container_registry" "this" {
  #checkov:skip=CKV_AZURE_139:public_network_access_enabled is user-configurable via var.acr.public_network_access_enabled (default false)
  #checkov:skip=CKV_AZURE_163:image vulnerability scanning is a subscription-level Defender for Cloud setting, not a property of this resource
  #checkov:skip=CKV_AZURE_164:trust_policy_enabled is user-configurable via var.acr.enable_trust_policy and only supported on the Premium SKU
  #checkov:skip=CKV_AZURE_165:georeplications are user-configurable via var.acr.georeplications and only supported on the Premium SKU
  #checkov:skip=CKV_AZURE_166:quarantine_policy_enabled is user-configurable via var.acr.quarantine_policy_enabled and only supported on the Premium SKU
  #checkov:skip=CKV_AZURE_233:zone_redundancy_enabled is user-configurable via var.acr.zone_redundancy_enabled (default true) and only supported on the Premium SKU
  #checkov:skip=CKV_AZURE_237:dedicated data endpoints are only supported on the Premium SKU and are not exposed by this module
  name                          = var.acr.name
  location                      = var.acr.location == null ? azurerm_resource_group.this[0].location : var.acr.location
  resource_group_name           = var.acr.resource_group_name == null ? azurerm_resource_group.this[0].name : var.acr.resource_group_name
  sku                           = var.acr.sku
  admin_enabled                 = var.acr.admin_enabled
  anonymous_pull_enabled        = var.acr.anonymous_pull_enabled
  retention_policy_in_days      = local.retention_policy_in_days
  export_policy_enabled         = local.export_policy_enabled
  network_rule_bypass_option    = var.acr.network_rule_bypass_option
  data_endpoint_enabled         = var.acr.data_endpoint_enabled
  public_network_access_enabled = var.acr.public_network_access_enabled
  quarantine_policy_enabled     = local.quarantine_policy_enabled
  trust_policy_enabled          = var.acr.enable_trust_policy
  zone_redundancy_enabled       = var.acr.zone_redundancy_enabled

  dynamic "encryption" {
    for_each = var.customer_managed_key != null ? { this = var.customer_managed_key } : {}

    content {
      identity_client_id = data.azurerm_user_assigned_identity.this[0].client_id
      key_vault_key_id   = data.azurerm_key_vault_key.this[0].versionless_id
    }
  }

  dynamic "georeplications" {
    for_each = local.ordered_geo_replications

    content {
      location                  = georeplications.value.location
      regional_endpoint_enabled = georeplications.value.regional_endpoint_enabled
      tags                      = georeplications.value.tags
      zone_redundancy_enabled   = georeplications.value.zone_redundancy_enabled
    }
  }

  dynamic "identity" {
    for_each = coalesce(local.identity_system_assigned_user_assigned, local.identity_system_assigned, local.identity_user_assigned, {})

    content {
      type         = identity.value.type
      identity_ids = identity.value.user_assigned_resource_ids
    }
  }

  # Only one network_rule_set block is allowed.
  # Create it if the variable is not null.
  dynamic "network_rule_set" {
    for_each = var.acr.network_rule_set != null ? { this = var.acr.network_rule_set } : {}

    content {
      default_action = network_rule_set.value.default_action

      dynamic "ip_rule" {
        for_each = network_rule_set.value.ip_rule

        content {
          action   = ip_rule.value.action
          ip_range = ip_rule.value.ip_range
        }
      }
    }
  }

  tags = merge(
    var.tags,
    tomap({
      "ResourceType" = "Container Registry"
    })
  )

  lifecycle {
    precondition {
      condition     = var.acr.zone_redundancy_enabled == false || var.acr.sku == "Premium"
      error_message = "The Premium SKU is required if zone redundancy is enabled."
    }
    precondition {
      condition     = var.acr.network_rule_set == null || var.acr.sku == "Premium"
      error_message = "The Premium SKU is required if a network rule set is defined."
    }
    precondition {
      condition     = var.customer_managed_key == null || var.acr.sku == "Premium"
      error_message = "The Premium SKU is required if a customer managed key is defined."
    }
    precondition {
      condition     = var.acr.public_network_access_enabled != false || var.acr.sku == "Premium"
      error_message = "The Premium SKU is required when public_network_access_enabled = false (private endpoints require Premium)."
    }
    precondition {
      condition     = var.acr.data_endpoint_enabled == false || var.acr.sku == "Premium"
      error_message = "The Premium SKU is required if a dedicated data endpoint is enabled."
    }
    precondition {
      condition     = var.acr.quarantine_policy_enabled == false || var.acr.sku == "Premium"
      error_message = "The Premium SKU is required if quarantine policy is enabled."
    }
    precondition {
      condition     = var.acr.export_policy_enabled == false || var.acr.sku == "Premium"
      error_message = "The Premium SKU is required if export policy is enabled."
    }
    precondition {
      condition     = var.acr.enable_trust_policy == false || var.acr.sku == "Premium"
      error_message = "The Premium SKU is required if trust policy (content trust) is enabled."
    }
    precondition {
      condition     = length(var.acr.georeplications) == 0 || var.acr.sku == "Premium"
      error_message = "The Premium SKU is required if georeplications are configured."
    }
    precondition {
      condition     = var.acr.anonymous_pull_enabled == false || contains(["Standard", "Premium"], var.acr.sku)
      error_message = "The Standard or Premium SKU is required if anonymous_pull_enabled is true."
    }
  }
}

resource "azurerm_role_assignment" "acr" {
  for_each = var.acr.role_assignments != null ? var.acr.role_assignments : {}

  scope                = azurerm_container_registry.this.id
  role_definition_name = each.value.role_definition_name
  principal_id         = each.value.principal_id
}

# Private Endpoint

module "private_endpoints" {
  source  = "schubergphilis-ep/mcaf-private-endpoints/azure"
  version = "0.4.1"

  count = var.acr.public_network_access_enabled == true ? 0 : 1

  location            = var.acr.location == null ? azurerm_resource_group.this[0].location : var.acr.location
  resource_group_name = var.acr.resource_group_name == null ? azurerm_resource_group.this[0].name : var.acr.resource_group_name

  private_endpoints = {
    "${var.acr.name}-pep" = {
      private_connection_resource_id          = azurerm_container_registry.this.id
      subnet_id                               = var.acr.pe_subnet
      subresource_name                        = "registry"
      is_manual_connection                    = false
      private_endpoints_manage_dns_zone_group = false
      tags = merge(
        var.tags,
        tomap({
          "ResourceType" = "Container Registry"
        })
      )
    }
  }
}

resource "azurerm_monitor_diagnostic_setting" "this" {
  for_each = var.diagnostic_settings

  name                           = each.value.name != null ? each.value.name : "diag-${var.acr.name}"
  target_resource_id             = azurerm_container_registry.this.id
  eventhub_authorization_rule_id = each.value.event_hub_authorization_rule_resource_id
  eventhub_name                  = each.value.event_hub_name
  log_analytics_destination_type = each.value.log_analytics_destination_type
  log_analytics_workspace_id     = each.value.workspace_resource_id
  partner_solution_id            = each.value.marketplace_partner_resource_id
  storage_account_id             = each.value.storage_account_resource_id

  dynamic "enabled_log" {
    for_each = each.value.log_categories

    content {
      category = enabled_log.value
    }
  }
  dynamic "enabled_log" {
    for_each = each.value.log_groups

    content {
      category_group = enabled_log.value
    }
  }
  dynamic "metric" {
    for_each = each.value.metric_categories

    content {
      category = metric.value
    }
  }
}

resource "azurerm_container_registry_credential_set" "credential_set" {
  for_each = { for idx, cred in var.credential_sets : cred.name => cred }

  name                  = each.value.name
  container_registry_id = azurerm_container_registry.this.id
  login_server          = each.value.login_server

  identity {
    type = "SystemAssigned"
  }

  dynamic "authentication_credentials" {
    for_each = each.value.authentication_credentials != null ? [each.value.authentication_credentials] : []
    content {
      username_secret_id = authentication_credentials.value.username_secret_id
      password_secret_id = authentication_credentials.value.password_secret_id
    }
  }

  lifecycle {
    precondition {
      # Credential sets are only useful with cache rules (their job is auth
      # for pull-through), and cache rules require Standard or Premium.
      condition     = contains(["Standard", "Premium"], var.acr.sku)
      error_message = "Credential sets require the Standard or Premium SKU."
    }
  }
}

resource "azurerm_container_registry_cache_rule" "this" {
  for_each = { for idx, rule in var.cache_rules : rule.name => rule }

  name                  = each.value.name
  container_registry_id = azurerm_container_registry.this.id
  target_repo           = each.value.target_repo
  source_repo           = each.value.source_repo
  credential_set_id     = each.value.credential_set_name != null ? "${azurerm_container_registry.this.id}/credentialSets/${each.value.credential_set_name}" : null

  lifecycle {
    precondition {
      # Per the Azure ACR SKU comparison: artifact cache rules are N/A on Basic.
      condition     = contains(["Standard", "Premium"], var.acr.sku)
      error_message = "Cache rules require the Standard or Premium SKU."
    }
  }
}