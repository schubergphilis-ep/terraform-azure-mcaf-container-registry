# Upgrading from v0.4.0 to v1.0.0

Version `1.0.0` adopts the **azurerm 5.x provider** and, as a consequence of
schema changes in that provider, removes and renames a number of inputs. This is
a breaking release: you must update both your provider configuration and your
module inputs before running `terraform plan`.

## 1. Upgrade the azurerm provider to 5.x

The module now requires:

```hcl
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5"
    }
  }
}
```

## 2. Removed input: `acr.enable_trust_policy`

Azure retired the Container Registry **content trust** feature, and the
`trust_policy_enabled` argument was removed from the azurerm 5.x provider. The
corresponding module input has been removed.

**Action:** delete `enable_trust_policy` from your `acr` object. There is no
replacement.

```diff
 acr = {
   name                = "myacr123"
   sku                 = "Premium"
-  enable_trust_policy = true
 }
```

## 3. Renamed input: `acr.georeplications[*].regional_endpoint_enabled` → `global_endpoint_routing_enabled`

In azurerm 5.x the `georeplications` block replaces `regional_endpoint_enabled`
with `global_endpoint_routing_enabled`. The module input follows the provider.

**Action:** rename the field in every georeplication entry.

```diff
 acr = {
   sku = "Premium"
   georeplications = [
     {
       location                        = "westeurope"
-      regional_endpoint_enabled       = true
+      global_endpoint_routing_enabled = true
       zone_redundancy_enabled         = true
     }
   ]
 }
```

## 4. Internal changes (no action required)

These changed under the hood and do not affect module inputs, but are listed so
you understand any plan diff you may see:

- The bundled `mcaf-private-endpoints` module was upgraded from `0.4.1` to
  `2.0.0` (private endpoints now use `subresource_names`). This only affects
  deployments with `public_network_access_enabled = false`.

## Upgrade checklist

1. Bump the module version to `1.0.0`.
2. Set the azurerm provider constraint to `~> 5` and run `terraform init -upgrade`.
3. Remove `enable_trust_policy` from the `acr` object.
4. Rename `regional_endpoint_enabled` to `global_endpoint_routing_enabled` in all
   `georeplications` entries.
5. Run `terraform plan` and review the diff carefully before applying.
