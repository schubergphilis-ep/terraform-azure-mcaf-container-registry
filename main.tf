resource "azurerm_resource_group" "this" {
  count = var.resource_group_name == null ? 0 : 1

  name     = var.resource_group_name
  location = var.location
}

resource "azurerm_container_registry" "this" {
  name                          = var.acr.name
  location                      = var.acr.location == null ? azurerm_resource_group.this[0].location : var.acr.location
  resource_group_name           = var.acr.resource_group_name == null ? azurerm_resource_group.this[0].name : var.acr.resource_group_name
  sku                           = var.acr.sku
  admin_enabled                 = var.acr.admin_enabled
  anonymous_pull_enabled        = var.acr.anonymous_pull_enabled
  # Premium-only fields are nulled on non-Premium SKUs so the attributes
  # never reach the Azure API (which would reject them on Basic/Standard).
  # Variable defaults stay non-null so Premium consumers see no behavior
  # change. The lifecycle preconditions below catch explicit opt-in on
  # non-Premium with a clear error before the API call is even attempted.
  retention_policy_in_days      = var.acr.sku == "Premium" ? var.acr.retention_policy_in_days : null
  export_policy_enabled         = var.acr.sku == "Premium" ? (var.acr.public_network_access_enabled ? true : var.acr.export_policy_enabled) : null
  network_rule_bypass_option    = var.acr.network_rule_bypass_option
  public_network_access_enabled = var.acr.public_network_access_enabled
  quarantine_policy_enabled     = var.acr.sku == "Premium" ? var.acr.quarantine_policy_enabled : null
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
      condition     = var.acr.zone_redundancy_enabled && var.acr.sku == "Premium" || !var.acr.zone_redundancy_enabled
      error_message = "The Premium SKU is required if zone redundancy is enabled."
    }
    precondition {
      condition     = var.acr.network_rule_set != null && var.acr.sku == "Premium" || var.acr.network_rule_set == null
      error_message = "The Premium SKU is required if a network rule set is defined."
    }
    precondition {
      condition     = var.customer_managed_key != null && var.acr.sku == "Premium" || var.customer_managed_key == null
      error_message = "The Premium SKU is required if a customer managed key is defined."
    }
    precondition {
      # Private link with private endpoints is Premium-only. The module
      # provisions a PE when public_network_access_enabled is false; gate
      # that combination here so apply fails fast with a clear message
      # rather than at the Azure API layer.
      condition     = var.acr.public_network_access_enabled || var.acr.sku == "Premium"
      error_message = "The Premium SKU is required when public_network_access_enabled = false (private endpoints require Premium)."
    }
    # Gates the three Premium-only policy fields on the actual value rather
    # than null-ness. The optional() defaults (false / false / 7) mean the
    # attributes are never null, so the previous null-based preconditions
    # were unreachable and Basic/Standard SKUs always errored even when the
    # caller hadn't opted into any Premium feature.
    precondition {
      condition     = !var.acr.quarantine_policy_enabled || var.acr.sku == "Premium"
      error_message = "The Premium SKU is required if quarantine policy is enabled."
    }
    precondition {
      # Treat `0` (the azurerm provider's "off" sentinel — see container
      # registry resource source) and `7` (this variable's default) as "no
      # opt-in". Any other value implies the caller is configuring retention
      # and needs Premium.
      condition     = contains([0, 7], var.acr.retention_policy_in_days) || var.acr.sku == "Premium"
      error_message = "The Premium SKU is required when retention_policy_in_days is set to a non-default value (allowed on non-Premium: 0 = off, 7 = default)."
    }
    precondition {
      condition     = !var.acr.export_policy_enabled || var.acr.sku == "Premium"
      error_message = "The Premium SKU is required if export policy is enabled."
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
  source = "github.com/schubergphilis/terraform-azure-mcaf-private-endpoints?ref=v0.4.1"

  count = var.acr.public_network_access_enabled == true ? 0 : 1

  location                      = var.acr.location == null ? azurerm_resource_group.this[0].location : var.acr.location
  resource_group_name           = var.acr.resource_group_name == null ? azurerm_resource_group.this[0].name : var.acr.resource_group_name
  
  private_endpoints = {
    "${var.acr.name}-pep" = {
      private_connection_resource_id = azurerm_container_registry.this.id
      subnet_id = var.acr.pe_subnet
      subresource_name = "registry"
      is_manual_connection = false
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
    type         = "SystemAssigned"
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