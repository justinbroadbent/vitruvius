mock_provider "azurerm" {
  # Synthetic IDs in proper Azure resource ID format so the
  # azurerm_management_group_policy_set_definition resource's client-side
  # validation accepts the reference format during apply-mode tests.
  mock_resource "azurerm_policy_definition" {
    defaults = {
      id = "/providers/Microsoft.Management/managementGroups/test-mg/providers/Microsoft.Authorization/policyDefinitions/mock-policy-definition"
    }
  }
  mock_resource "azurerm_management_group_policy_set_definition" {
    defaults = {
      id = "/providers/Microsoft.Management/managementGroups/test-mg/providers/Microsoft.Authorization/policySetDefinitions/mock-policy-set"
    }
  }
  mock_resource "azurerm_management_group_policy_assignment" {
    defaults = {
      id = "/providers/Microsoft.Management/managementGroups/test-mg/providers/Microsoft.Authorization/policyAssignments/mock-assignment"
    }
  }
}

variables {
  owner                = "platform-team"
  env                  = "dev"
  cost_center          = "cc-1001"
  data_classification  = "internal"
  business_criticality = "tier-2"
}

run "required_tags_are_present" {
  command = plan

  assert {
    condition = (
      output.tags["owner"] == "platform-team" &&
      output.tags["env"] == "dev" &&
      output.tags["cost-center"] == "cc-1001" &&
      output.tags["data-classification"] == "internal" &&
      output.tags["business-criticality"] == "tier-2"
    )
    error_message = "required tags missing or wrong values in tags output"
  }
}

run "optional_tags_absent_when_not_supplied" {
  command = plan

  assert {
    condition     = !contains(keys(output.tags), "app")
    error_message = "app tag should be absent when not supplied"
  }

  assert {
    condition     = !contains(keys(output.tags), "component")
    error_message = "component tag should be absent when not supplied"
  }

  assert {
    condition     = !contains(keys(output.tags), "lifecycle")
    error_message = "lifecycle tag should be absent when lifecycle_stage is not supplied"
  }
}

run "optional_tags_present_when_supplied" {
  command = plan

  variables {
    app             = "memberapi"
    component       = "core"
    lifecycle_stage = "experimental"
  }

  assert {
    condition = (
      output.tags["app"] == "memberapi" &&
      output.tags["component"] == "core" &&
      output.tags["lifecycle"] == "experimental"
    )
    error_message = "optional tags should be present when supplied; lifecycle_stage should emit as 'lifecycle' key"
  }
}

run "required_tags_subset_excludes_optional" {
  command = plan

  variables {
    app = "memberapi"
  }

  assert {
    condition     = !contains(keys(output.required_tags), "app")
    error_message = "required_tags output must not include optional tags"
  }

  assert {
    condition     = length(keys(output.required_tags)) == 5
    error_message = "required_tags must contain exactly 5 keys per ADR 0010"
  }
}

run "vocabularies_match_adr_0010" {
  command = plan

  assert {
    condition = (
      length(setsubtract(["prod", "staging", "dev", "sandbox"], output.vocabularies.env)) == 0 &&
      length(output.vocabularies.env) == 4
    )
    error_message = "env vocabulary must match ADR 0010 exactly"
  }

  assert {
    condition = (
      length(setsubtract(["public", "internal", "confidential", "restricted"], output.vocabularies.data_classification)) == 0 &&
      length(output.vocabularies.data_classification) == 4
    )
    error_message = "data_classification vocabulary must match ADR 0010 exactly"
  }

  assert {
    condition = (
      length(setsubtract(["tier-0", "tier-1", "tier-2", "tier-3"], output.vocabularies.business_criticality)) == 0 &&
      length(output.vocabularies.business_criticality) == 4
    )
    error_message = "business_criticality vocabulary must match ADR 0010 exactly"
  }
}

run "policy_not_deployed_when_mg_id_null" {
  command = plan

  assert {
    condition     = output.initiative_id == null
    error_message = "initiative_id must be null when policy_management_group_id is not supplied"
  }

  assert {
    condition     = output.assignment_id == null
    error_message = "assignment_id must be null when policy_management_group_id is not supplied"
  }

  assert {
    condition     = length(output.policy_definition_ids) == 0
    error_message = "policy_definition_ids must be empty when policy is not deployed"
  }
}

run "policy_deployed_when_mg_id_supplied" {
  # Uses apply so the mock_provider supplies values for computed IDs.
  command = apply

  variables {
    policy_management_group_id = "/providers/Microsoft.Management/managementGroups/test-mg"
  }

  assert {
    condition     = length(output.policy_definition_ids) == 10
    error_message = "policy_definition_ids must contain all 10 definitions when policy is deployed"
  }

  # 8 direct + 5 inherit instantiations + 5 require-on-rg instantiations.
  assert {
    condition     = length(azurerm_management_group_policy_set_definition.this[0].policy_definition_reference) == 18
    error_message = "initiative must carry 8 direct references plus the two 5-way per-tag fan-outs (inherit, require-on-rg)"
  }

  assert {
    condition     = output.initiative_id != null
    error_message = "initiative_id must be non-null when policy is deployed"
  }

  assert {
    condition     = output.assignment_id != null
    error_message = "assignment_id must be non-null when policy is deployed"
  }
}
