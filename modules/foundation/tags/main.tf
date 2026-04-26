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
  }
  policy_definitions = {
    for k, file in local.policy_files :
    k => jsondecode(file("${path.module}/policy/${file}"))
  }

  # Required tags are inheritable from the resource group; optional tags are not.
  inheritable_tag_keys = ["owner", "env", "cost-center", "data-classification", "business-criticality"]

  # Direct references: every definition except the parameterized inherit policy.
  direct_references = [
    for k in sort(keys(local.policy_files)) : {
      reference_id     = k
      definition_key   = k
      parameter_values = jsonencode({})
    } if k != "inherit-tag-from-resource-group"
  ]

  # Inherit references: one per inheritable required tag.
  inherit_references = [
    for tag in local.inheritable_tag_keys : {
      reference_id     = "inherit-${tag}"
      definition_key   = "inherit-tag-from-resource-group"
      parameter_values = jsonencode({ tagName = { value = tag } })
    }
  ]

  initiative_references = concat(local.direct_references, local.inherit_references)
}

resource "azurerm_policy_definition" "this" {
  for_each = { for k, v in local.policy_definitions : k => v if local.deploy_policy }

  name                = "vitruvius-tags-${each.key}"
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

  name                = "vitruvius-tag-taxonomy"
  policy_type         = "Custom"
  display_name        = "Vitruvius — Tag Taxonomy (ADR 0010)"
  description         = "Bundles the required-tag, allowed-values, and inherit-from-resource-group policies that enforce the tag taxonomy in ADR 0010. Audit-before-Deny lifecycle per ADR 0008."
  management_group_id = var.policy_management_group_id

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

  name                 = "vitruvius-tag-taxonomy"
  management_group_id  = var.policy_management_group_id
  policy_definition_id = azurerm_management_group_policy_set_definition.this[0].id
  display_name         = "Vitruvius — Tag Taxonomy"
  description          = "Assigns the tag taxonomy initiative. Defaults to DoNotEnforce for the Audit period (ADR 0008); promote via policy_enforcement_mode once telemetry supports it."
  enforce              = var.policy_enforcement_mode == "Default"
  location             = var.policy_assignment_location

  identity {
    type = "SystemAssigned"
  }
}
