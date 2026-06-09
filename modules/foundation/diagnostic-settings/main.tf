locals {
  deploy_policy = var.policy_management_group_id != null

  # Policy definitions ship as JSON in policy/. Each file is the full
  # definition body; we read and decode at plan time.
  policy_files = {
    "keyvault-route-to-substrate"    = "keyvault-route-to-substrate.json"
    "aks-route-to-substrate"         = "aks-route-to-substrate.json"
    "service-bus-route-to-substrate" = "service-bus-route-to-substrate.json"
    "app-service-route-to-substrate" = "app-service-route-to-substrate.json"
    "apim-route-to-substrate"        = "apim-route-to-substrate.json"
  }
  policy_definitions = {
    for k, file in local.policy_files :
    k => jsondecode(file("${path.module}/policy/${file}"))
  }

  covered_resource_types = sort([
    for k, def in local.policy_definitions : def.policyRule.if.equals
  ])

  # Initiative references: one per definition, all pointing the initiative's
  # logAnalyticsWorkspaceId parameter at the per-definition parameter.
  initiative_references = [
    for k in sort(keys(local.policy_files)) : {
      reference_id   = k
      definition_key = k
      parameter_values = jsonencode({
        effect                  = { value = "[parameters('effect')]" }
        logAnalyticsWorkspaceId = { value = "[parameters('logAnalyticsWorkspaceId')]" }
      })
    }
  ]

  deploy_assignment = local.deploy_policy && var.policy_assignment_scope != null
}

# Cross-variable validation: when policy is being deployed, the LAW ID must
# be supplied. Variable-level validation in Terraform 1.7 cannot reference
# other variables (added in 1.9); the precondition pattern works in 1.7+.
resource "terraform_data" "input_invariants" {
  lifecycle {
    precondition {
      condition     = !local.deploy_policy || var.log_analytics_workspace_id != null
      error_message = "log_analytics_workspace_id is required when policy_management_group_id is supplied — the initiative needs a routing target."
    }
  }
}

resource "azurerm_policy_definition" "this" {
  for_each = { for k, v in local.policy_definitions : k => v if local.deploy_policy }

  name                = "vitruvius-diag-${each.key}"
  policy_type         = "Custom"
  mode                = each.value.mode
  display_name        = each.value.displayName
  description         = each.value.description
  policy_rule         = jsonencode(each.value.policyRule)
  parameters          = jsonencode(each.value.parameters)
  management_group_id = var.policy_management_group_id
}

resource "azurerm_management_group_policy_set_definition" "this" {
  count = local.deploy_policy ? 1 : 0

  name                = "vitruvius-substrate-diagnostic-settings"
  policy_type         = "Custom"
  display_name        = "Vitruvius — Substrate diagnostic-settings routing (ADR 0005)"
  description         = "Bundles the per-resource-type policies that route diagnostic settings to the platform Log Analytics workspace. Implements ADR 0005's substrate guarantee. Audit-before-Deny lifecycle per ADR 0008: defaults to AuditIfNotExists; promote to DeployIfNotExists once Audit-mode evidence supports it."
  management_group_id = var.policy_management_group_id

  parameters = jsonencode({
    effect = {
      type = "String"
      metadata = {
        displayName = "Effect"
        description = "Initiative-level effect parameter; flows to every member policy."
      }
      allowedValues = ["AuditIfNotExists", "DeployIfNotExists", "Disabled"]
      defaultValue  = var.policy_effect
    }
    logAnalyticsWorkspaceId = {
      type = "String"
      metadata = {
        displayName = "Log Analytics Workspace ID"
        description = "Resource ID of the platform LAW. Flows to every member policy."
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

resource "azurerm_management_group_policy_assignment" "this" {
  count = local.deploy_assignment ? 1 : 0

  name                 = "vitruvius-substrate-diag"
  management_group_id  = var.policy_assignment_scope
  policy_definition_id = azurerm_management_group_policy_set_definition.this[0].id
  display_name         = "Vitruvius — Substrate diagnostic-settings"
  description          = "Assigns the substrate diagnostic-settings initiative. Per ADR 0008, defaults to DoNotEnforce for the Audit period; promote via policy_enforcement_mode once telemetry supports it."
  enforce              = var.policy_enforcement_mode == "Default"
  location             = var.policy_assignment_location

  identity {
    type = "SystemAssigned"
  }

  parameters = jsonencode({
    effect = {
      value = var.policy_effect
    }
    logAnalyticsWorkspaceId = {
      value = var.log_analytics_workspace_id
    }
  })
}

# The member policies' roleDefinitionIds are granted automatically when an
# assignment is created through the portal — but not by Terraform. Without
# these grants every DeployIfNotExists remediation fails authorization.
resource "azurerm_role_assignment" "remediation" {
  for_each = local.deploy_assignment ? toset(["Log Analytics Contributor", "Monitoring Contributor"]) : toset([])

  scope                = var.policy_assignment_scope
  role_definition_name = each.value
  principal_id         = azurerm_management_group_policy_assignment.this[0].identity[0].principal_id
}
