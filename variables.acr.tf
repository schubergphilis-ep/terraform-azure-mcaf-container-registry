variable "acr" {
  type = object({
    name                          = optional(string)
    resource_group_name           = optional(string)
    location                      = optional(string)
    sku                           = optional(string, "Premium")
    anonymous_pull_enabled        = optional(bool, false)
    quarantine_policy_enabled     = optional(bool, false)
    admin_enabled                 = optional(bool, false)
    public_network_access_enabled = optional(bool, false)
    data_endpoint_enabled         = optional(bool, false)
    role_assignment_mode          = optional(string)
    enable_trust_policy           = optional(bool, false)
    export_policy_enabled         = optional(bool, false)
    retention_policy_in_days      = optional(number, 7)
    network_rule_bypass_option    = optional(string, "None")
    managed_identities = optional(object({
      system_assigned            = optional(bool, false)
      user_assigned_resource_ids = optional(set(string), [])
    }), {})
    network_rule_set = optional(object({
      default_action = optional(string, "Deny")
      ip_rule = optional(list(object({
        # since the `action` property only permits `Allow`, this is hard-coded.
        action   = optional(string, "Allow")
        ip_range = string
      })), [])
    }), null)
    pe_subnet = optional(string, null)
    georeplications = optional(list(object({
      location                  = string
      regional_endpoint_enabled = optional(bool, true)
      zone_redundancy_enabled   = optional(bool, true)
      tags                      = optional(map(any), null)
    })), [])
    zone_redundancy_enabled = optional(bool, true)
    role_assignments = optional(map(object({
      principal_id         = string
      role_definition_name = string
    })))
    tags = optional(map(string))
  })
  default     = {}
  nullable    = false
  description = <<ACR_DETAILS
This object describes the configuration for an Azure Container Registry.

- `name` - (Optional) Specifies the name of the Container Registry. Changing this forces a new resource to be created.
- `resource_group_name` - (Optional) The name of the resource group in which to create the Container Registry. Changing this forces a new resource to be created.
- `location` - (Optional) Specifies the supported Azure location where the resource exists. Changing this forces a new resource to be created.
- `sku` - (Optional) The SKU name of the the Container Registry. Possible values are `Basic`, `Premium`.
- `admin_enabled` - (Optional) Specifies whether the admin user is enabled. Defaults to `false`.
- `anonymous_pull_enabled` - (Optional) Specifies whether anonymous pull is enabled. Defaults to `false`.
- `quarantine_policy_enabled` - (Optional) Specifies whether quarantine policy is enabled. Defaults to `false`.
- `public_network_access_enabled` - (Optional) Specifies whether public network access is enabled. Defaults to `false`.
- `role_assignment_mode` - (Optional) Selects how role assignments on the registry are evaluated: `AbacRepositoryPermissions` for repository-scoped permissions via ABAC conditions, or `LegacyRegistryPermissions` for registry-wide roles. Unset leaves the provider default, so an existing registry keeps whatever it has.
- `data_endpoint_enabled` - (Optional) Specifies whether a dedicated data endpoint is enabled. Required for pulls over a private endpoint: without it clients are redirected to a regional data host that is not served privately, and the pull fails after a successful authentication. Premium only. Defaults to `false`.
- `export_policy_enabled` - (Optional) Specifies whether export policy is enabled. Defaults to `false`.
- `retention_policy_in_days` - (Optional) Specifies the number of days to retain untagged manifests. Defaults to `7`.
- `network_bypass` - (Optional) Specifies the network bypass options. Possible values are `AzureServices`, `None`, and `ServiceEndpoints`.
- `managed_identities` - (Optional) Specifies the Managed Identity configuration. The following properties can be specified:
  - `system_assigned` - (Optional) Specifies if the System Assigned Managed Identity should be enabled. Defaults to `false`.
  - `user_assigned_resource_ids` - (Optional) Specifies a list of User Assigned Managed Identity resource IDs to be assigned to this resource. Defaults to `[]`.
- `network_rule_set` - (Optional) Specifies the network rule set configuration. The following properties can be specified:
  - `default_action` - (Optional) Specifies the default action for network rule set. Possible values are `Allow` and `Deny`. Defaults to `Deny`.
  - `ip_rule` - (Optional) Specifies the IP rule configuration. The following properties can be specified:
    - `action` - (Optional) Specifies the action for the IP rule. Possible values are `Allow` and `Deny`. Defaults to `Allow`.
    - `ip_range` - (Required) Specifies the IP range for the IP rule.
- `zone_redundancy_enabled` - (Optional) Specifies whether zone redundancy is enabled. Defaults to `tru`.
- `role_assignments` - (Optional) Specifies the role assignments for the Container Registry. The following properties can be specified:
  - `principal_id` - (Required) The ID of the principal to assign the role to.
  - `role` - (Required) The role to assign to the principal. Possible values are `AcrPull`, `AcrPush`
- `tags` - (Optional) A mapping of tags to assign to the resource.

Example Inputs:

```hcl

module "acr" {
  source = "somelocation"

  acr = {
    name                          = "myacr123"
    resource_group_name           = "myrg"
    location                      = "germanywestcentral"
    admin_enabled                 = false
    public_network_access_enabled = false
    network_rule_bypass_option    = "AzureServices"
  }
  tags = {
    "deploymentmodel" = "Terraform"
  }
}

```
}
ACR_DETAILS

  validation {
    condition     = can(regex("^[[:alnum:]]{5,50}$", var.acr.name))
    error_message = "The name must be between 5 and 50 characters long and can only contain letters and numbers."
  }
  validation {
    condition     = var.acr.role_assignments == null ? true : alltrue([for ra in var.acr.role_assignments : ra.role_definition_name == "AcrPush" || ra.role_definition_name == "AcrPull"])
    error_message = "All role definitions must be either 'AcrPull' or 'AcrPush'."
  }
  validation {
    condition     = var.acr.retention_policy_in_days >= 0 && var.acr.retention_policy_in_days <= 365
    error_message = "retention_policy_in_days must be between 0 and 365 (inclusive)."
  }
}

variable "customer_managed_key" {
  type = object({
    key_vault_resource_id = string
    key_name              = string
    key_version           = optional(string, null)
    user_assigned_identity = optional(object({
      resource_id = string
    }), null)
  })
  default     = null
  description = <<DESCRIPTION
A map of diagnostic settings to create on the Key Vault. The map key is deliberately arbitrary to avoid issues where map keys maybe unknown at plan time.
Controls the Customer managed key configuration on this resource. The following properties can be specified:
- `key_vault_resource_id` - (Required) Resource ID of the Key Vault that the customer managed key belongs to.
- `key_name` - (Required) Specifies the name of the Customer Managed Key Vault Key.
- `key_version` - (Optional) The version of the Customer Managed Key Vault Key.
- `user_assigned_identity` - (Optional) The User Assigned Identity that has access to the key.
  - `resource_id` - (Required) The resource ID of the User Assigned Identity that has access to the key.
DESCRIPTION
}

variable "credential_sets" {
  type = list(object({
    name         = string
    login_server = string
    authentication_credentials = optional(object({
      username_secret_id = string
      password_secret_id = string
    }))
  }))
  default     = []
  description = <<CREDENTIAL_SETS_DETAILS
This variable describes the configuration for credential sets in an Azure Container Registry.

- `name` - (Required) Specifies the name of the Credential Set. Changing this forces a new resource to be created.
- `login_server` - (Required) Specifies the login server for the credential set, such as "docker.io" or "ghcr.io".
- `authentication_credentials` - (Optional) Specifies the authentication credentials configuration. The following properties can be specified:
  - `username_secret_id` - (Required) Specifies the Key Vault Secret URL containing the username for the external registry.
  - `password_secret_id` - (Required) Specifies the Key Vault Secret URL containing the password for the external registry.

Example Inputs:
```hcl
module "acr" {
  source = "somelocation"
  
  credential_sets = [
    {
      name         = "dockerhub"
      login_server = "docker.io"
      authentication_credentials = {
        username_secret_id = "https://example-keyvault.vault.azure.net/secrets/docker-username"
        password_secret_id = "https://example-keyvault.vault.azure.net/secrets/docker-password"
      }
    },
    {
      name         = "ghcr"
      login_server = "ghcr.io"
      identity = {
        type = "UserAssigned"
        identity_ids = ["id1", "id2"]
      }
    }
  ]
}
CREDENTIAL_SETS_DETAILS
}

variable "cache_rules" {
  type = list(object({
    name                = string
    target_repo         = string
    source_repo         = string
    credential_set_name = optional(string)
  }))
  default     = []
  description = <<CACHE_RULES_DETAILS
This variable describes the configuration for cache rules in an Azure Container Registry.

    name - (Required) Specifies the name of the Cache Rule. Changing this forces a new resource to be created.
    target_repo - (Required) Specifies the target repository name in the Azure Container Registry where cached images will be stored.
    source_repo - (Required) Specifies the source repository name to be cached, including the fully qualified registry hostname (e.g., "docker.io/hello-world").
    credential_set_name - (Optional) Specifies the name of the credential set to use for authentication with the source repository. If provided, the credential set must be defined in the credential_sets variable.

Example Inputs:

hcl

module "acr" {
  source = "somelocation"
  
  cache_rules = [
    {
      name                = "cache-nginx"
      target_repo         = "nginx"
      source_repo         = "docker.io/nginx"
      credential_set_name = "dockerhub"
    },
    {
      name                = "cache-ubuntu"
      target_repo         = "ubuntu"
      source_repo         = "docker.io/ubuntu"
      credential_set_name = "dockerhub"
    }
  ]
}

CACHE_RULES_DETAILS
}
