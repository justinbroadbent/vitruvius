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

# --- Length-overflow safety (long workload exercises the hash-suffix path) ---

run "overflowed_storage_account_stays_within_limit_and_valid" {
  command = plan

  variables {
    workload = "member-portal-x"
    env      = "staging"
    region   = "germanywestcentral" # unknown region → long fallback abbreviation
  }

  assert {
    condition     = length(output.names.storage_account) <= 24
    error_message = "storage_account must respect Azure's 24-char limit even when parts overflow"
  }

  assert {
    condition     = can(regex("^[a-z0-9]{3,24}$", output.names.storage_account))
    error_message = "storage_account must be 3-24 lowercase alphanumeric chars (no hyphens)"
  }
}

run "overflowed_key_vault_stays_valid_no_trailing_hyphen" {
  command = plan

  variables {
    workload = "member-portal-x"
    env      = "staging"
    region   = "germanywestcentral"
  }

  assert {
    condition     = length(output.names.key_vault) <= 24
    error_message = "key_vault must respect Azure's 24-char limit even when parts overflow"
  }

  # Azure Key Vault: starts with a letter, alphanumeric or single hyphens,
  # no consecutive hyphens, no trailing hyphen.
  assert {
    condition     = can(regex("^kv-[a-z0-9]+(-[a-z0-9]+)*$", output.names.key_vault))
    error_message = "key_vault must not end in a hyphen or contain consecutive hyphens after truncation"
  }
}

run "overflowed_storage_account_carries_deterministic_hash" {
  command = plan

  variables {
    workload = "member-portal-x"
    region   = "germanywestcentral"
    env      = "prod"
  }

  # Asserts the overflowed name embeds a deterministic hash of the FULL parts.
  # Because the hash is over parts that include env/region/instance, changing any
  # of them changes the name — proving those disambiguators are not silently
  # dropped (the pre-fix collision bug).
  assert {
    condition     = output.names.storage_account == "st${substr(output.parts.compact, 0, 18)}${substr(md5(output.parts.hyphen), 0, 4)}"
    error_message = "overflowed storage_account must carry a deterministic hash of the full parts, keeping environments/instances distinct"
  }
}
