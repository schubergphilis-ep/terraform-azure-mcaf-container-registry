locals {
  identity_system_assigned_user_assigned = (var.acr.managed_identities.system_assigned && (length(var.acr.managed_identities.user_assigned_resource_ids) > 0 || var.customer_managed_key != null)) ? {
    this = {
      type                       = "SystemAssigned, UserAssigned"
      user_assigned_resource_ids = setunion(var.acr.managed_identities.user_assigned_resource_ids, try([data.azurerm_user_assigned_identity.this[0].id], []))
    }
  } : null
  identity_system_assigned = var.acr.managed_identities.system_assigned ? {
    this = {
      type                       = "SystemAssigned"
      user_assigned_resource_ids = null
    }
  } : null
  identity_user_assigned = (length(var.acr.managed_identities.user_assigned_resource_ids) > 0 || var.customer_managed_key != null) ? {
    this = {
      type                       = "UserAssigned"
      user_assigned_resource_ids = setunion(var.acr.managed_identities.user_assigned_resource_ids, try([data.azurerm_user_assigned_identity.this[0].id], []))
    }
  } : null

  ordered_geo_replications = { for geo in var.acr.georeplications : geo.location => geo }

  # Premium-only fields are nulled on non-Premium SKUs so the attributes
  # never reach the Azure API (which would reject them on Basic/Standard).
  # Variable defaults stay non-null so Premium consumers see no behavior
  # change. Lifecycle preconditions on the registry resource catch explicit
  # opt-in on non-Premium with a clear error before the API call is made.
  retention_policy_in_days  = var.acr.sku == "Premium" ? var.acr.retention_policy_in_days : null
  export_policy_enabled     = var.acr.sku == "Premium" ? (var.acr.public_network_access_enabled ? true : var.acr.export_policy_enabled) : null
  quarantine_policy_enabled = var.acr.sku == "Premium" ? var.acr.quarantine_policy_enabled : null
}