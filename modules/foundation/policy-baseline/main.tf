locals {
  deploy_policy = var.policy_management_group_id != null

  # Each guardrail ships as a full policy definition in policy/. These are
  # Deny/Audit policies (not DeployIfNotExists), so — unlike the diagnostic
  # safety net — no managed identity or remediation role grants are needed.
  policy_files = {
    "app-service-no-public-access" = "app-service-no-public-access.json"
    "app-service-https-only"       = "app-service-https-only.json"
    "storage-no-public-blob"       = "storage-no-public-blob.json"
    "allowed-locations"            = "allowed-locations.json"
  }
  policy_definitions = {
    for k, file in local.policy_files :
    k => jsondecode(file("${path.module}/policy/${file}"))
  }

  guardrail_policies = sort(keys(local.policy_files))

  # Initiative references: every guardrail receives the initiative-level
  # `effect`. The allowed-locations guardrail additionally receives the
  # approved-region list.
  initiative_references = [
    for k in local.guardrail_policies : {
      reference_id   = k
      definition_key = k
      parameter_values = jsonencode(merge(
        { effect = { value = "[parameters('effect')]" } },
        k == "allowed-locations" ? { listOfAllowedLocations = { value = "[parameters('listOfAllowedLocations')]" } } : {}
      ))
    }
  ]

  deploy_assignment = local.deploy_policy && var.policy_assignment_scope != null
}

# Cross-variable invariant: an empty allowed-region list would make the
# allowed-locations guardrail deny every region. Variable-level validation in
# Terraform 1.7 cannot reference other variables; the precondition pattern can.
resource "terraform_data" "input_invariants" {
  lifecycle {
    precondition {
      condition     = !local.deploy_policy || length(var.allowed_locations) > 0
      error_message = "allowed_locations must be non-empty when policy_management_group_id is supplied — an empty list would make the allowed-locations guardrail deny every region."
    }
  }
}

resource "azurerm_policy_definition" "this" {
  for_each = { for k, v in local.policy_definitions : k => v if local.deploy_policy }

  name                = "${var.name_prefix}-base-${each.key}"
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

  name                = "${var.name_prefix}-policy-baseline"
  policy_type         = "Custom"
  display_name        = "${title(var.name_prefix)} — Estate policy baseline (ADR 0025)"
  description         = "Estate-wide guardrails every subscription beneath the management group inherits: App Service public-access and HTTPS, Storage public-blob access, and approved regions. Mandatory controls are platform-owned (ADR 0025 §1), not optional workload bricks. Audit-before-Deny per ADR 0008: defaults to Audit; promote to Deny once Audit-mode evidence supports it."
  management_group_id = var.policy_management_group_id

  parameters = jsonencode({
    effect = {
      type = "String"
      metadata = {
        displayName = "Effect"
        description = "Initiative-level effect; flows to every guardrail. Audit-before-Deny per ADR 0008."
      }
      allowedValues = ["Audit", "Deny", "Disabled"]
      defaultValue  = var.policy_effect
    }
    listOfAllowedLocations = {
      type = "Array"
      metadata = {
        displayName = "Allowed locations"
        description = "Approved Azure regions. Resources outside this list fail the allowed-locations guardrail."
        strongType  = "location"
      }
      defaultValue = var.allowed_locations
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

  name                 = "${var.name_prefix}-baseline"
  management_group_id  = var.policy_assignment_scope
  policy_definition_id = azurerm_management_group_policy_set_definition.this[0].id
  display_name         = "${title(var.name_prefix)} — Estate policy baseline"
  description          = "Assigns the estate policy baseline. Per ADR 0008, defaults to DoNotEnforce for the Audit period; promote via policy_enforcement_mode once evidence supports it."
  enforce              = var.policy_enforcement_mode == "Default"

  # Deny/Audit policies remediate nothing, so the assignment needs no
  # managed identity (and therefore no location).
  parameters = jsonencode({
    effect = {
      value = var.policy_effect
    }
    listOfAllowedLocations = {
      value = var.allowed_locations
    }
  })
}
