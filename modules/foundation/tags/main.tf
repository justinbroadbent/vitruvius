locals {
  required_tags = {
    "owner"                = var.owner
    "env"                  = var.env
    "cost-center"          = var.cost_center
    "data-classification"  = var.data_classification
    "business-criticality" = var.business_criticality
  }

  optional_tags_raw = {
    "app"       = var.app
    "component" = var.component
    "lifecycle" = var.lifecycle_stage
  }
  optional_tags = { for k, v in local.optional_tags_raw : k => v if v != null }

  tags = merge(local.required_tags, local.optional_tags)

  # Vocabulary metadata. Surfaced as an output so consumers and Backstage can
  # render allowed-values dropdowns from a single source of truth.
  vocabularies = {
    env                  = ["prod", "staging", "dev", "sandbox"]
    data_classification  = ["public", "internal", "confidential", "restricted"]
    business_criticality = ["tier-0", "tier-1", "tier-2", "tier-3"]
    lifecycle            = ["stable", "experimental", "deprecated"]
  }

  deploy_policy = var.policy_management_group_id != null

  # Policy definitions ship as JSON in policy/. Each file is the full
  # definition body; we read and decode at plan time.
  policy_files = {
    "require-tag-owner"                   = "require-tag-owner.json"
    "require-tag-env"                     = "require-tag-env.json"
    "require-tag-cost-center"             = "require-tag-cost-center.json"
    "require-tag-data-classification"     = "require-tag-data-classification.json"
    "require-tag-business-criticality"    = "require-tag-business-criticality.json"
    "allowed-values-env"                  = "allowed-values-env.json"
    "allowed-values-data-classification"  = "allowed-values-data-classification.json"
    "allowed-values-business-criticality" = "allowed-values-business-criticality.json"
    "inherit-tag-from-resource-group"     = "inherit-tag-from-resource-group.json"
    "require-tag-on-resource-group"       = "require-tag-on-resource-group.json"
  }
  policy_definitions = {
    for k, file in local.policy_files :
    k => jsondecode(file("${path.module}/policy/${file}"))
  }

  # Required tags are inheritable from the resource group; optional tags are not.
  inheritable_tag_keys = ["owner", "env", "cost-center", "data-classification", "business-criticality"]

  # The two parameterized definitions are instantiated once per required tag
  # rather than referenced directly.
  parameterized_definitions = ["inherit-tag-from-resource-group", "require-tag-on-resource-group"]

  # Direct references: every non-parameterized definition, wired to the
  # initiative-level effect parameter so the Audit→Deny promotion (ADR 0008)
  # is a single assignment-time change, not a per-definition JSON edit.
  direct_references = [
    for k in sort(keys(local.policy_files)) : {
      reference_id     = k
      definition_key   = k
      parameter_values = jsonencode({ effect = { value = "[parameters('effect')]" } })
    } if !contains(local.parameterized_definitions, k)
  ]

  # Inherit references: one per inheritable required tag.
  inherit_references = [
    for tag in local.inheritable_tag_keys : {
      reference_id     = "inherit-${tag}"
      definition_key   = "inherit-tag-from-resource-group"
      parameter_values = jsonencode({ tagName = { value = tag } })
    }
  ]

  # Resource-group references: the require-tag-* policies run in Indexed mode,
  # which excludes resource groups — but resource groups are the inherit
  # policy's source, so the taxonomy is enforced there via a mode-All policy.
  rg_required_references = [
    for tag in local.inheritable_tag_keys : {
      reference_id   = "require-on-rg-${tag}"
      definition_key = "require-tag-on-resource-group"
      parameter_values = jsonencode({
        tagName = { value = tag }
        effect  = { value = "[parameters('effect')]" }
      })
    }
  ]

  initiative_references = concat(local.direct_references, local.inherit_references, local.rg_required_references)
}

# The allowed-values policy JSONs and local.vocabularies encode the same
# vocabulary in two places (ADR 0010 requires both: Terraform validates inputs,
# Azure Policy validates the estate). This invariant fails any plan — including
# every terraform test run — if the two drift.
resource "terraform_data" "vocabulary_invariants" {
  lifecycle {
    precondition {
      condition = alltrue([
        for pair in [
          { file = "env", key = "env" },
          { file = "data-classification", key = "data_classification" },
          { file = "business-criticality", key = "business_criticality" },
        ] :
        sort(jsondecode(file("${path.module}/policy/allowed-values-${pair.file}.json")).policyRule.if.allOf[1].notIn) == sort(local.vocabularies[pair.key])
      ])
      error_message = "The allowed-values-*.json vocabularies have drifted from local.vocabularies in main.tf. ADR 0010 requires the two stay identical — update both together."
    }
  }
}

resource "azurerm_policy_definition" "this" {
  for_each = { for k, v in local.policy_definitions : k => v if local.deploy_policy }

  name                = "${var.name_prefix}-tags-${each.key}"
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

  name                = "${var.name_prefix}-tag-taxonomy"
  policy_type         = "Custom"
  display_name        = "${title(var.name_prefix)} — Tag Taxonomy (ADR 0010)"
  description         = "Bundles the required-tag, allowed-values, and inherit-from-resource-group policies that enforce the tag taxonomy in ADR 0010. Audit-before-Deny lifecycle per ADR 0008."
  management_group_id = var.policy_management_group_id

  parameters = jsonencode({
    effect = {
      type = "String"
      metadata = {
        displayName = "Effect"
        description = "Initiative-level effect; flows to every require/allowed-values member policy. The inherit members are modify-effect and unaffected."
      }
      allowedValues = ["Audit", "Deny", "Disabled"]
      defaultValue  = var.policy_effect
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
  count = local.deploy_policy ? 1 : 0

  name                 = "${var.name_prefix}-tag-taxonomy"
  management_group_id  = var.policy_management_group_id
  policy_definition_id = azurerm_management_group_policy_set_definition.this[0].id
  display_name         = "${title(var.name_prefix)} — Tag Taxonomy"
  description          = "Assigns the tag taxonomy initiative. Defaults to DoNotEnforce for the Audit period (ADR 0008); promote via policy_enforcement_mode once telemetry supports it."
  enforce              = var.policy_enforcement_mode == "Default"
  location             = var.policy_assignment_location

  identity {
    type = "SystemAssigned"
  }

  parameters = jsonencode({
    effect = {
      value = var.policy_effect
    }
  })
}

# The inherit policy's roleDefinitionIds are granted automatically when an
# assignment is created through the portal — but not by Terraform. Without
# this grant every modify-effect remediation fails authorization.
resource "azurerm_role_assignment" "remediation" {
  count = local.deploy_policy ? 1 : 0

  scope                = var.policy_management_group_id
  role_definition_name = "Tag Contributor"
  principal_id         = azurerm_management_group_policy_assignment.this[0].identity[0].principal_id
}
