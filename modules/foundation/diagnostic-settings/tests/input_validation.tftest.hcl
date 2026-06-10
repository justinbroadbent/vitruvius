mock_provider "azurerm" {}

run "valid_no_op_inputs_succeed" {
  command = plan

  assert {
    condition     = output.initiative_id == null
    error_message = "module should be a no-op with default inputs"
  }
}

run "rejects_off_vocabulary_effect" {
  command = plan

  variables {
    policy_effect = "Audit"
  }

  expect_failures = [var.policy_effect]
}

run "rejects_off_vocabulary_enforcement_mode" {
  command = plan

  variables {
    policy_enforcement_mode = "Audit"
  }

  expect_failures = [var.policy_enforcement_mode]
}

run "rejects_malformed_law_id" {
  command = plan

  variables {
    log_analytics_workspace_id = "not-a-resource-id"
  }

  expect_failures = [var.log_analytics_workspace_id]
}

run "rejects_assignment_location_with_uppercase" {
  command = plan

  variables {
    policy_assignment_location = "EastUS"
  }

  expect_failures = [var.policy_assignment_location]
}

run "rejects_bare_management_group_name" {
  command = plan

  variables {
    policy_management_group_id = "platform-mg"
    log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-platform/providers/Microsoft.OperationalInsights/workspaces/log-platform"
  }

  expect_failures = [var.policy_management_group_id]
}

run "rejects_law_id_missing_workspace_segment" {
  command = plan

  variables {
    log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-platform"
  }

  expect_failures = [var.log_analytics_workspace_id]
}

run "rejects_invalid_name_prefix" {
  command = plan

  variables {
    name_prefix = "Platform"
  }

  expect_failures = [var.name_prefix]
}
