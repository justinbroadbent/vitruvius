locals {
  # Inputs are validated; lower-case for safety in the few cases that matter.
  org_clean      = lower(var.org)
  workload_clean = lower(var.workload)
  env_clean      = lower(var.env)
  region_clean   = lower(var.region)

  # Region abbreviations. Extend in PR per README.
  # In practice, most consumers use only a small subset (typically a primary
  # region plus one for failover). The broader list is retained for
  # portability and to avoid future PRs when an integration requires another
  # region. Unrecognized regions fall back to the unmodified region name.
  region_abbreviations = {
    "eastus"      = "eus"
    "eastus2"     = "eus2"
    "westus"      = "wus"
    "westus2"     = "wus2"
    "westus3"     = "wus3"
    "centralus"   = "cus"
    "northeurope" = "neu"
    "westeurope"  = "weu"
    "uksouth"     = "uks"
    "ukwest"      = "ukw"
  }
  region_abbr = lookup(local.region_abbreviations, local.region_clean, local.region_clean)

  # Composed name parts.
  parts_hyphen  = "${local.org_clean}-${local.workload_clean}-${local.env_clean}-${local.region_abbr}-${var.instance}"
  parts_compact = "${local.org_clean}${replace(local.workload_clean, "-", "")}${local.env_clean}${local.region_abbr}${var.instance}"

  # Length-constrained resources (storage account, key vault) can overflow their
  # Azure limit once workload + env + region + instance are concatenated. A naive
  # right-truncation is unsafe: it silently drops the env/region/instance suffix,
  # so two environments of the same workload — or two instances — collapse to the
  # SAME name. For globally-unique resource types that is a deploy-time collision,
  # not a cosmetic issue. Instead, when a name overflows we replace the dropped
  # tail with a short deterministic hash of the FULL parts, preserving uniqueness.
  # Short names (the common case) keep their readable, hash-free form unchanged.
  name_hash = substr(md5(local.parts_hyphen), 0, 4)

  # Storage account: alphanumeric lower, 3-24 chars. 24 = len("st") + 18 + len(hash).
  storage_account_full = "st${local.parts_compact}"
  storage_account = (
    length(local.storage_account_full) <= 24
    ? local.storage_account_full
    : "st${substr(local.parts_compact, 0, 18)}${local.name_hash}"
  )

  # Container registry: alphanumeric, 5-50 chars. 50 = len("cr") + 44 + len(hash).
  container_registry_full = "cr${local.parts_compact}"
  container_registry = (
    length(local.container_registry_full) <= 50
    ? local.container_registry_full
    : "cr${substr(local.parts_compact, 0, 44)}${local.name_hash}"
  )

  # Key Vault: 3-24 chars, hyphens OK but no leading/trailing or consecutive
  # hyphen. trimsuffix guards against the truncation boundary landing on a "-",
  # which would otherwise produce "…--<hash>". 24 = len("kv-") + 15 + len("-") + len(hash).
  key_vault_full = "kv-${local.parts_hyphen}"
  key_vault = (
    length(local.key_vault_full) <= 24
    ? local.key_vault_full
    : "kv-${trimsuffix(substr(local.parts_hyphen, 0, 15), "-")}-${local.name_hash}"
  )

  names = {
    resource_group          = "rg-${local.parts_hyphen}"
    virtual_network         = "vnet-${local.parts_hyphen}"
    subnet                  = "snet-${local.parts_hyphen}"
    network_security_group  = "nsg-${local.parts_hyphen}"
    public_ip               = "pip-${local.parts_hyphen}"
    private_endpoint        = "pe-${local.parts_hyphen}"
    storage_account         = local.storage_account
    key_vault               = local.key_vault
    container_registry      = local.container_registry
    aks_cluster             = "aks-${local.parts_hyphen}"
    application_insights    = "appi-${local.parts_hyphen}"
    log_analytics_workspace = "log-${local.parts_hyphen}"
    function_app            = "func-${local.parts_hyphen}"
    app_service_plan        = "asp-${local.parts_hyphen}"
    managed_identity        = "id-${local.parts_hyphen}"
  }
}
