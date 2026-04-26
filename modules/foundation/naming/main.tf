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

  # Per-resource-type construction with constraints.
  # Storage account: alphanumeric lower, 3-24 chars.
  storage_account = substr("st${local.parts_compact}", 0, 24)
  # Container registry: alphanumeric, 5-50 chars.
  container_registry = substr("cr${local.parts_compact}", 0, 50)
  # Key Vault: 3-24 chars, hyphens OK.
  key_vault = substr("kv-${local.parts_hyphen}", 0, 24)

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
