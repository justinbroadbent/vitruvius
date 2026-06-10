data "azurerm_client_config" "current" {}

# --- Workload identity primitives ---

resource "azurerm_user_assigned_identity" "workload" {
  name                = var.user_assigned_identity_name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

# Federates the AKS service account to the UAI. The app team creates the
# matching ServiceAccount in Kubernetes with these annotations:
#   azure.workload.identity/client-id: <module.workload_identity_client_id>
#   azure.workload.identity/tenant-id: <data.azurerm_client_config.current.tenant_id>
# Per ADR 0009, secrets are ephemeral by default — workload identity replaces
# any need for a static client secret.
resource "azurerm_federated_identity_credential" "aks" {
  name                      = "fic-aks-${var.aks_namespace}-${var.aks_service_account_name}"
  user_assigned_identity_id = azurerm_user_assigned_identity.workload.id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = var.aks_oidc_issuer_url
  subject                   = "system:serviceaccount:${var.aks_namespace}:${var.aks_service_account_name}"
}

# --- Key Vault via AVM (per ADR 0001) ---

module "key_vault" {
  source  = "Azure/avm-res-keyvault-vault/azurerm"
  version = "0.10.2"

  # Keeps terraform test hermetic and avoids sending AVM usage telemetry
  # from platform infrastructure. Do not flip it on.
  enable_telemetry = false

  name                = var.key_vault_name
  resource_group_name = var.resource_group_name
  location            = var.location
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = var.key_vault_sku

  soft_delete_retention_days    = var.key_vault_soft_delete_retention_days
  purge_protection_enabled      = true
  public_network_access_enabled = false
  # RBAC authorization is the AVM module's default (legacy_access_policies_enabled = false).

  # With public access off and default-Deny ACLs, the vault is reachable only
  # through a private endpoint — supply at least one or the workload identity
  # has a role on a vault it cannot reach.
  private_endpoints = var.private_endpoints

  tags = var.tags

  diagnostic_settings = {
    to_substrate_law = {
      name                  = "diag-to-law"
      workspace_resource_id = var.log_analytics_workspace_id
      log_groups            = ["allLogs"]
      metric_categories     = ["AllMetrics"]
    }
  }

  role_assignments = {
    workload_identity_secrets_user = {
      principal_id               = azurerm_user_assigned_identity.workload.principal_id
      role_definition_id_or_name = "Key Vault Secrets User"
    }
  }
}

# --- Policy definitions, initiative, and (optional) assignment ---

locals {
  policy_files = {
    "keyvault-purge-protection-required"    = "keyvault-purge-protection-required.json"
    "keyvault-rbac-authorization-required"  = "keyvault-rbac-authorization-required.json"
    "keyvault-diagnostic-settings-required" = "keyvault-diagnostic-settings-required.json"
  }
  policy_definitions = {
    for k, file in local.policy_files :
    k => jsondecode(file("${path.module}/policy/${file}"))
  }

  # Azure policy resource names are subscription-scoped, and one invocation of
  # this module = one workload. Deriving names from the (globally unique) Key
  # Vault name keeps a second workload in the same subscription from colliding.
  # Short codes keep definition names inside Azure's 64-char limit.
  policy_short_names = {
    "keyvault-purge-protection-required"    = "kv-purge"
    "keyvault-rbac-authorization-required"  = "kv-rbac"
    "keyvault-diagnostic-settings-required" = "kv-diag"
  }
  initiative_name = "${var.name_prefix}-kv-hardening-${var.key_vault_name}"

  # Member parameters wire to the initiative-level parameters so the
  # Audit→Deny promotion (ADR 0008) is one assignment-time change.
  initiative_parameter_values = {
    "keyvault-purge-protection-required"   = jsonencode({ effect = { value = "[parameters('effect')]" } })
    "keyvault-rbac-authorization-required" = jsonencode({ effect = { value = "[parameters('effect')]" } })
    "keyvault-diagnostic-settings-required" = jsonencode({
      logAnalyticsWorkspaceId = { value = "[parameters('logAnalyticsWorkspaceId')]" }
    })
  }

  initiative_references = [
    for k in sort(keys(local.policy_files)) : {
      reference_id     = k
      definition_key   = k
      parameter_values = local.initiative_parameter_values[k]
    }
  ]

  deploy_assignment = var.policy_assignment_scope != null
  # The assignment scope is the input value itself, used as the actual scope —
  # not merely as an on/off flag. A subscription scope is exactly
  # /subscriptions/{guid}; a deeper path (…/resourceGroups/…) is a resource-group
  # scope and requires a different assignment resource. Audit-before-Deny (ADR
  # 0008) often pilots enforcement on a single resource group before promoting to
  # the whole subscription, so both are first-class.
  assign_at_subscription   = local.deploy_assignment && can(regex("^/subscriptions/[0-9a-fA-F-]{36}$", var.policy_assignment_scope))
  assign_at_resource_group = local.deploy_assignment && !local.assign_at_subscription
}

resource "azurerm_policy_definition" "this" {
  for_each = local.policy_definitions

  name         = "${var.name_prefix}-${local.policy_short_names[each.key]}-${var.key_vault_name}"
  policy_type  = "Custom"
  mode         = each.value.mode
  display_name = "${each.value.displayName} (${var.key_vault_name})"
  description  = each.value.description
  policy_rule  = jsonencode(each.value.policyRule)
  parameters   = jsonencode(each.value.parameters)
}

resource "azurerm_policy_set_definition" "this" {
  name         = local.initiative_name
  policy_type  = "Custom"
  display_name = "${title(var.name_prefix)} — web-api-aks Key Vault hardening (${var.key_vault_name})"
  description  = "Bundles the Key Vault hardening policies that every web-api-aks workload's Key Vault must comply with: purge protection, RBAC authorization, and diagnostic settings to the platform LAW. Audit-before-Deny lifecycle per ADR 0008."

  parameters = jsonencode({
    effect = {
      type = "String"
      metadata = {
        displayName = "Effect"
        description = "Initiative-level effect; flows to the purge-protection and RBAC member policies. The diagnostic-settings member is AuditIfNotExists and unaffected."
      }
      allowedValues = ["Audit", "Deny", "Disabled"]
      defaultValue  = var.policy_effect
    }
    logAnalyticsWorkspaceId = {
      type = "String"
      metadata = {
        displayName = "Log Analytics Workspace ID"
        description = "Resource ID of the platform LAW the vault's diagnostics must route to."
      }
      defaultValue = var.log_analytics_workspace_id
    }
  })

  dynamic "policy_definition_reference" {
    for_each = local.initiative_references
    content {
      policy_definition_id = azurerm_policy_definition.this[policy_definition_reference.value.definition_key].id
      reference_id         = policy_definition_reference.value.reference_id
      parameter_values     = policy_definition_reference.value.parameter_values
    }
  }
}

# No managed identity on either assignment: the initiative is Audit /
# AuditIfNotExists only, and identities are required only for DeployIfNotExists
# and Modify remediation.
resource "azurerm_subscription_policy_assignment" "this" {
  count = local.assign_at_subscription ? 1 : 0

  name                 = local.initiative_name
  subscription_id      = var.policy_assignment_scope
  policy_definition_id = azurerm_policy_set_definition.this.id
  display_name         = "${title(var.name_prefix)} — web-api-aks Key Vault hardening (${var.key_vault_name})"
  description          = "Assigns the workload-pattern's KV hardening initiative. Defaults to DoNotEnforce for the Audit period (ADR 0008); promote via policy_enforcement_mode once telemetry supports it."
  enforce              = var.policy_enforcement_mode == "Default"

  parameters = jsonencode({
    effect                  = { value = var.policy_effect }
    logAnalyticsWorkspaceId = { value = var.log_analytics_workspace_id }
  })
}

resource "azurerm_resource_group_policy_assignment" "this" {
  count = local.assign_at_resource_group ? 1 : 0

  name                 = local.initiative_name
  resource_group_id    = var.policy_assignment_scope
  policy_definition_id = azurerm_policy_set_definition.this.id
  display_name         = "${title(var.name_prefix)} — web-api-aks Key Vault hardening (${var.key_vault_name})"
  description          = "Assigns the workload-pattern's KV hardening initiative. Defaults to DoNotEnforce for the Audit period (ADR 0008); promote via policy_enforcement_mode once telemetry supports it."
  enforce              = var.policy_enforcement_mode == "Default"

  parameters = jsonencode({
    effect                  = { value = var.policy_effect }
    logAnalyticsWorkspaceId = { value = var.log_analytics_workspace_id }
  })
}
