terraform {
  required_version = ">= 1.9.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0.0"
    }
  }

  # In the app team's real repo this block points at their own state
  # container (ADR 0017): one state file per workload, per environment.
  # backend "azurerm" { ... }
}

provider "azurerm" {
  features {}
}

# ---------------------------------------------------------------------------
# An app team's root, end to end. This file is what a workload team copies
# into THEIR repository when they onboard onto the web-api-aks golden path.
# Everything platform-owned arrives through variables (see variables.tf for
# where each value comes from); everything team-owned is right here.
#
# In this repo the module sources are relative paths because the example
# lives next to the modules. A real team pins a release tag instead:
#
#   source = "git::https://<host>/<org>/vitruvius.git//modules/workload-patterns/web-api-aks?ref=v0.1.0"
#
# See README.md § "How you consume the modules".
# ---------------------------------------------------------------------------

# Names come from the platform convention — never invented locally.
module "naming" {
  source = "../../modules/foundation/naming"

  org      = var.org
  workload = "paylink"
  env      = var.env
  region   = var.location
}

# Tags come from the taxonomy. Tag-map mode only: the policy initiative that
# enforces the taxonomy is assigned once, estate-wide, by the platform — an
# app team never deploys tag policy itself.
module "tags" {
  source = "../../modules/foundation/tags"

  owner                = "payments-team"
  env                  = var.env
  cost_center          = "cc-3003"
  data_classification  = "confidential"
  business_criticality = "tier-1"

  app             = "paylink"
  component       = "api"
  lifecycle_stage = "experimental"
}

# The team owns its resource group (ADR 0004: consumers own RGs).
resource "azurerm_resource_group" "workload" {
  name     = module.naming.names.resource_group
  location = var.location
  tags     = module.tags.tags
}

# The golden path. Identity, secrets, diagnostics routing, and the
# KV-hardening policy bundle all arrive with this one call.
module "web_api" {
  source = "../../modules/workload-patterns/web-api-aks"

  # From naming/tags above — platform conventions, locally computed.
  user_assigned_identity_name = module.naming.names.managed_identity
  key_vault_name              = module.naming.names.key_vault
  resource_group_name         = azurerm_resource_group.workload.name
  location                    = var.location
  tags                        = module.tags.tags

  # Team-owned Kubernetes facts: must match the ServiceAccount the team
  # creates in its namespace (see README step 5).
  aks_namespace            = "paylink"
  aks_service_account_name = "paylink-api"

  # Platform-published facts, handed over as values (never read from
  # platform state):
  aks_oidc_issuer_url        = var.aks_oidc_issuer_url
  log_analytics_workspace_id = var.log_analytics_workspace_id

  # The vault is private-only; the platform's spoke network supplies the
  # subnet and DNS zone (ADR 0018).
  private_endpoints = {
    workload_subnet = {
      subnet_resource_id            = var.private_endpoint_subnet_id
      private_dns_zone_resource_ids = [var.key_vault_dns_zone_id]
    }
  }

  # Audit-before-Deny (ADR 0008): the hardening bundle observes first.
  name_prefix             = var.org
  policy_assignment_scope = var.policy_assignment_scope
  policy_enforcement_mode = "DoNotEnforce"
}
