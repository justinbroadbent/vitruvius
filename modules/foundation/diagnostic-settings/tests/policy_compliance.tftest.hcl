mock_provider "azurerm" {
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

run "no_op_when_mg_id_null" {
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

run "covered_resource_types_enumerates_all_five" {
  command = plan

  assert {
    condition     = length(output.covered_resource_types) == 5
    error_message = "covered_resource_types must list all five resource types this v0.1.0 covers"
  }

  assert {
    condition = (
      contains(output.covered_resource_types, "Microsoft.KeyVault/vaults") &&
      contains(output.covered_resource_types, "Microsoft.ContainerService/managedClusters") &&
      contains(output.covered_resource_types, "Microsoft.ServiceBus/namespaces") &&
      contains(output.covered_resource_types, "Microsoft.Web/sites") &&
      contains(output.covered_resource_types, "Microsoft.ApiManagement/service")
    )
    error_message = "covered_resource_types must include the documented v0.1.0 set"
  }
}

run "definitions_and_initiative_created_when_mg_id_supplied" {
  command = apply

  variables {
    policy_management_group_id = "/providers/Microsoft.Management/managementGroups/test-mg"
    log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.OperationalInsights/workspaces/test-law"
  }

  assert {
    condition     = length(output.policy_definition_ids) == 5
    error_message = "policy_definition_ids must contain all five definitions when policy is deployed"
  }

  assert {
    condition     = output.initiative_id != null
    error_message = "initiative_id must be non-null when policy is deployed"
  }

  assert {
    condition     = output.assignment_id == null
    error_message = "assignment_id must be null when policy_assignment_scope is not supplied"
  }
}

run "assignment_created_when_scope_supplied" {
  command = apply

  variables {
    policy_management_group_id = "/providers/Microsoft.Management/managementGroups/test-mg"
    policy_assignment_scope    = "/providers/Microsoft.Management/managementGroups/test-mg"
    log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.OperationalInsights/workspaces/test-law"
  }

  assert {
    condition     = output.assignment_id != null
    error_message = "assignment_id must be non-null when policy_assignment_scope is supplied"
  }

  assert {
    condition     = azurerm_management_group_policy_assignment.this[0].enforce == false
    error_message = "default policy_enforcement_mode of DoNotEnforce must produce enforce=false (Audit-before-Deny per ADR 0008)"
  }
}

run "initiative_bundles_all_five_policies" {
  command = apply

  variables {
    policy_management_group_id = "/providers/Microsoft.Management/managementGroups/test-mg"
    log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.OperationalInsights/workspaces/test-law"
  }

  assert {
    condition     = length(azurerm_management_group_policy_set_definition.this[0].policy_definition_reference) == 5
    error_message = "initiative must reference all five member policies"
  }
}

run "missing_law_when_deploying_is_rejected" {
  command = plan

  variables {
    policy_management_group_id = "/providers/Microsoft.Management/managementGroups/test-mg"
    # log_analytics_workspace_id intentionally omitted
  }

  expect_failures = [terraform_data.input_invariants]
}
