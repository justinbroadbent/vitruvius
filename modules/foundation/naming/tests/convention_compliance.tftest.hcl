variables {
  org      = "wsx"
  workload = "demo"
  env      = "dev"
  region   = "eastus"
  instance = "01"
}

run "resource_group_matches_convention" {
  command = plan

  assert {
    condition     = output.names.resource_group == "rg-wsx-demo-dev-eus-01"
    error_message = "resource_group name does not match expected convention"
  }
}

run "virtual_network_matches_convention" {
  command = plan

  assert {
    condition     = output.names.virtual_network == "vnet-wsx-demo-dev-eus-01"
    error_message = "virtual_network name does not match expected convention"
  }
}

run "storage_account_is_compact_and_within_limit" {
  command = plan

  assert {
    condition     = output.names.storage_account == "stwsxdemodeveus01"
    error_message = "storage_account name should be compact (no hyphens) and follow the convention"
  }

  assert {
    condition     = length(output.names.storage_account) <= 24
    error_message = "storage_account name exceeds Azure 24-char limit"
  }
}

run "key_vault_within_limit" {
  command = plan

  assert {
    condition     = length(output.names.key_vault) <= 24
    error_message = "key_vault name exceeds Azure 24-char limit"
  }
}

run "container_registry_is_compact" {
  command = plan

  assert {
    condition     = output.names.container_registry == "crwsxdemodeveus01"
    error_message = "container_registry name should be compact (no hyphens)"
  }

  assert {
    condition     = length(output.names.container_registry) <= 50
    error_message = "container_registry name exceeds Azure 50-char limit"
  }
}

run "region_abbr_known_region" {
  command = plan

  assert {
    condition     = output.region_abbr == "eus"
    error_message = "eastus should map to eus"
  }
}

run "region_abbr_falls_back_for_unknown_region" {
  command = plan

  variables {
    region = "unknownregion"
  }

  assert {
    condition     = output.region_abbr == "unknownregion"
    error_message = "unknown region should fall back to the unmodified region name"
  }
}

run "parts_are_exposed" {
  command = plan

  assert {
    condition     = output.parts.hyphen == "wsx-demo-dev-eus-01"
    error_message = "parts.hyphen should expose the composed hyphenated name parts"
  }

  assert {
    condition     = output.parts.compact == "wsxdemodeveus01"
    error_message = "parts.compact should expose the composed compact name parts"
  }
}

run "instance_override_is_honored" {
  command = plan

  variables {
    instance = "07"
  }

  assert {
    condition     = output.names.resource_group == "rg-wsx-demo-dev-eus-07"
    error_message = "instance override should propagate to all hyphenated names"
  }
}
