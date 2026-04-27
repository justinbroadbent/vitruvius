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
