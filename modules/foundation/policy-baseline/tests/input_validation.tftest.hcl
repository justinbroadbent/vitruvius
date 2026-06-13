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
    policy_effect = "AuditIfNotExists"
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

run "rejects_bare_management_group_name" {
  command = plan

  variables {
    policy_management_group_id = "platform-mg"
  }

  expect_failures = [var.policy_management_group_id]
}

run "rejects_invalid_name_prefix" {
  command = plan

  variables {
    name_prefix = "Platform"
  }

  expect_failures = [var.name_prefix]
}

run "rejects_uppercase_region" {
  command = plan

  variables {
    allowed_locations = ["EastUS"]
  }

  expect_failures = [var.allowed_locations]
}
