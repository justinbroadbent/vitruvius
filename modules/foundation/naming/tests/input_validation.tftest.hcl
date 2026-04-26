run "valid_inputs_produce_output" {
  command = plan

  variables {
    org      = "wsx"
    workload = "demo"
    env      = "dev"
    region   = "eastus"
  }

  assert {
    condition     = output.names != null
    error_message = "valid inputs should produce a names output"
  }
}

run "rejects_uppercase_org" {
  command = plan

  variables {
    org      = "WSX"
    workload = "demo"
    env      = "dev"
    region   = "eastus"
  }

  expect_failures = [var.org]
}

run "rejects_too_short_org" {
  command = plan

  variables {
    org      = "a"
    workload = "demo"
    env      = "dev"
    region   = "eastus"
  }

  expect_failures = [var.org]
}

run "rejects_workload_with_underscore" {
  command = plan

  variables {
    org      = "wsx"
    workload = "demo_app"
    env      = "dev"
    region   = "eastus"
  }

  expect_failures = [var.workload]
}

run "rejects_off_vocabulary_env" {
  command = plan

  variables {
    org      = "wsx"
    workload = "demo"
    env      = "production"
    region   = "eastus"
  }

  expect_failures = [var.env]
}

run "rejects_region_with_spaces" {
  command = plan

  variables {
    org      = "wsx"
    workload = "demo"
    env      = "dev"
    region   = "East US"
  }

  expect_failures = [var.region]
}

run "rejects_single_digit_instance" {
  command = plan

  variables {
    org      = "wsx"
    workload = "demo"
    env      = "dev"
    region   = "eastus"
    instance = "1"
  }

  expect_failures = [var.instance]
}
