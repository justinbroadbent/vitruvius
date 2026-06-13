# Reference environment root: a platform landing zone composed from the
# foundation and platform-services modules. The values here are illustrative —
# an operator copies this root and substitutes their own org code, region,
# management group, and subscription.
#
# Composition is by output data (ADR 0004): each module's outputs feed the next
# module's inputs at this consumer boundary. No module imports another.

terraform {
  required_version = ">= 1.9.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0.0"
    }
  }
}

provider "azurerm" {
  features {}
  # subscription_id is supplied at apply time via ARM_SUBSCRIPTION_ID or -var.
}

# Conventions — canonical names and the tag map every resource carries.

module "naming" {
  source = "../../modules/foundation/naming"

  org      = var.org
  workload = "platform"
  env      = var.env
  region   = var.location
}

module "tags" {
  source = "../../modules/foundation/tags"

  owner                = "platform-team"
  env                  = var.env
  cost_center          = "cc-1001"
  data_classification  = "internal"
  business_criticality = "tier-1"
}

# The platform resource group. The consumer root owns resource groups; the
# modules take the name and never create it (ADR 0004 / ADR 0024).

resource "azurerm_resource_group" "platform" {
  name     = module.naming.names.resource_group
  location = var.location
  tags     = module.tags.tags
}

# Platform identities — the deploy and policy-remediation UAIs.

module "identity" {
  source = "../../modules/foundation/identity"

  resource_group_name = azurerm_resource_group.platform.name
  location            = var.location
  tags                = module.tags.tags
}

# The observability substrate. Names come from naming; its workspace ID is the
# seam the diagnostic-settings initiative routes to.

module "observability_substrate" {
  source = "../../modules/platform-services/observability-substrate"

  # Platform-library artifacts (alerts, policy objects) carry the org code as
  # their prefix; the module default is the generic 'platform'.
  name_prefix = var.org

  log_analytics_workspace_name = module.naming.names.log_analytics_workspace
  application_insights_name    = module.naming.names.application_insights
  resource_group_name          = azurerm_resource_group.platform.name
  location                     = var.location
  tags                         = module.tags.tags
}

# Substrate-routing policy. diagnostic-settings consumes the substrate's
# workspace ID — the end-to-end seam this root wires together.
# Audit-before-Deny defaults (ADR 0008).

module "diagnostic_settings" {
  source = "../../modules/foundation/diagnostic-settings"

  name_prefix                = var.org
  policy_management_group_id = var.platform_management_group_id
  policy_assignment_scope    = var.platform_management_group_id
  log_analytics_workspace_id = module.observability_substrate.log_analytics_workspace_id
  policy_assignment_location = var.location
}

# The estate guardrail baseline (ADR 0025 §1). Mandatory Deny/Audit policies —
# no public App Services, HTTPS-only, no public blobs, approved regions —
# assigned at the platform MG so every subscription beneath it inherits them,
# golden path or not. Ships Audit-first (ADR 0008); a later PR promotes to Deny.

module "policy_baseline" {
  source = "../../modules/foundation/policy-baseline"

  name_prefix                = var.org
  policy_management_group_id = var.platform_management_group_id
  policy_assignment_scope    = var.platform_management_group_id
  allowed_locations          = [var.location]
}

# The hub network's decided core (ADR 0018): hub VNet, centralized private
# DNS, and the AMPLS that makes the substrate's private-by-default posture
# actually work — the substrate's IDs are scoped in right here, in the open.
# Egress enforcement (the firewall) is the v0.2 build (issue #9).

module "hub" {
  source = "../../modules/networking/hub"

  virtual_network_name = module.naming.names.virtual_network
  resource_group_name  = azurerm_resource_group.platform.name
  location             = var.location
  tags                 = module.tags.tags
  address_space        = var.hub_address_space

  subnets = {
    private-endpoints = { address_prefixes = var.hub_private_endpoint_prefixes }
  }

  ampls_linked_resource_ids = {
    law  = module.observability_substrate.log_analytics_workspace_id
    appi = module.observability_substrate.application_insights_id
  }
  ampls_private_endpoint_subnet_key = "private-endpoints"
  ampls_private_endpoint_name       = module.naming.names.private_endpoint
}
