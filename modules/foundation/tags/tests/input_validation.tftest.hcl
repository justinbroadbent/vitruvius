mock_provider "azurerm" {}

run "valid_inputs_produce_output" {
  command = plan

  variables {
    owner                = "platform-team"
    env                  = "dev"
    cost_center          = "cc-1001"
    data_classification  = "internal"
    business_criticality = "tier-2"
  }

  assert {
    condition     = output.tags != null
    error_message = "valid inputs should produce a tags output"
  }
}

run "rejects_off_vocabulary_env" {
  command = plan

  variables {
    owner                = "platform-team"
    env                  = "production"
    cost_center          = "cc-1001"
    data_classification  = "internal"
    business_criticality = "tier-2"
  }

  expect_failures = [var.env]
}

run "rejects_off_vocabulary_data_classification" {
  command = plan

  variables {
    owner                = "platform-team"
    env                  = "dev"
    cost_center          = "cc-1001"
    data_classification  = "secret"
    business_criticality = "tier-2"
  }

  expect_failures = [var.data_classification]
}

run "rejects_off_vocabulary_business_criticality" {
  command = plan

  variables {
    owner                = "platform-team"
    env                  = "dev"
    cost_center          = "cc-1001"
    data_classification  = "internal"
    business_criticality = "critical"
  }

  expect_failures = [var.business_criticality]
}

run "rejects_malformed_cost_center" {
  command = plan

  variables {
    owner                = "platform-team"
    env                  = "dev"
    cost_center          = "1001"
    data_classification  = "internal"
    business_criticality = "tier-2"
  }

  expect_failures = [var.cost_center]
}

run "rejects_person_name_owner" {
  command = plan

  variables {
    owner                = "Jane.Doe"
    env                  = "dev"
    cost_center          = "cc-1001"
    data_classification  = "internal"
    business_criticality = "tier-2"
  }

  expect_failures = [var.owner]
}

run "rejects_off_vocabulary_lifecycle_stage" {
  command = plan

  variables {
    owner                = "platform-team"
    env                  = "dev"
    cost_center          = "cc-1001"
    data_classification  = "internal"
    business_criticality = "tier-2"
    lifecycle_stage      = "retired"
  }

  expect_failures = [var.lifecycle_stage]
}

run "rejects_invalid_policy_enforcement_mode" {
  command = plan

  variables {
    owner                   = "platform-team"
    env                     = "dev"
    cost_center             = "cc-1001"
    data_classification     = "internal"
    business_criticality    = "tier-2"
    policy_enforcement_mode = "Audit"
  }

  expect_failures = [var.policy_enforcement_mode]
}

run "rejects_too_short_app" {
  command = plan

  variables {
    owner                = "platform-team"
    env                  = "dev"
    cost_center          = "cc-1001"
    data_classification  = "internal"
    business_criticality = "tier-2"
    app                  = "x"
  }

  expect_failures = [var.app]
}

run "rejects_component_with_underscore" {
  command = plan

  variables {
    owner                = "platform-team"
    env                  = "dev"
    cost_center          = "cc-1001"
    data_classification  = "internal"
    business_criticality = "tier-2"
    component            = "api_layer"
  }

  expect_failures = [var.component]
}

run "rejects_bare_management_group_name" {
  command = plan

  variables {
    owner                      = "platform-team"
    env                        = "dev"
    cost_center                = "cc-1001"
    data_classification        = "internal"
    business_criticality       = "tier-2"
    policy_management_group_id = "platform-mg"
  }

  expect_failures = [var.policy_management_group_id]
}

run "rejects_invalid_name_prefix" {
  command = plan

  variables {
    owner                = "platform-team"
    env                  = "dev"
    cost_center          = "cc-1001"
    data_classification  = "internal"
    business_criticality = "tier-2"
    name_prefix          = "Platform"
  }

  expect_failures = [var.name_prefix]
}
