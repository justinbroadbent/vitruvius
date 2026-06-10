data "azurerm_client_config" "current" {}

locals {
  # The AVM virtualnetwork module is azapi-based and takes the resource
  # group's full resource ID (parent_id), not its name.
  resource_group_id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${var.resource_group_name}"

  ampls_name                  = coalesce(var.ampls_name, "ampls-${var.virtual_network_name}")
  ampls_private_endpoint_name = coalesce(var.ampls_private_endpoint_name, "pep-ampls-${var.virtual_network_name}")
  # The contains() guard keeps an invalid subnet key from evaluating the
  # endpoint at all, so the input_invariants precondition owns the error.
  create_ampls_endpoint = var.create_ampls && var.ampls_private_endpoint_subnet_key != null && contains(keys(var.subnets), coalesce(var.ampls_private_endpoint_subnet_key, "-"))

  # The AMPLS endpoint resolves through the Azure Monitor zone set; the DNS
  # zone group wires whichever of those zones this hub actually hosts.
  ampls_dns_zone_names = [
    "privatelink.monitor.azure.com",
    "privatelink.oms.opinsights.azure.com",
    "privatelink.ods.opinsights.azure.com",
    "privatelink.agentsvc.azure-automation.net",
    "privatelink.blob.core.windows.net",
  ]
  ampls_dns_zone_ids = [
    for z in local.ampls_dns_zone_names :
    module.private_dns_zones[z].resource_id if contains(var.private_dns_zones, z)
  ]
}

# Cross-variable invariant: an AMPLS private endpoint needs a subnet that
# actually exists in this hub.
resource "terraform_data" "input_invariants" {
  lifecycle {
    precondition {
      condition     = var.ampls_private_endpoint_subnet_key == null || contains(keys(var.subnets), coalesce(var.ampls_private_endpoint_subnet_key, "-"))
      error_message = "ampls_private_endpoint_subnet_key must name a key in var.subnets."
    }
  }
}

# --- Hub VNet via AVM (ADR 0001) ---
# The shared-services network every spoke peers to (ADR 0018). Spoke peering
# happens at the consumer boundary (ADR 0004): this module exposes the
# surface; it does not reach into spokes.
module "virtual_network" {
  source  = "Azure/avm-res-network-virtualnetwork/azurerm"
  version = "0.11.0"

  # Keeps terraform test hermetic and avoids sending AVM usage telemetry
  # from platform infrastructure. Do not flip it on.
  enable_telemetry = false

  name          = var.virtual_network_name
  parent_id     = local.resource_group_id
  location      = var.location
  address_space = var.address_space
  tags          = var.tags

  subnets = {
    for k, s in var.subnets : k => {
      name             = k
      address_prefixes = s.address_prefixes
    }
  }
}

# --- Centralized private DNS zones via AVM (ADR 0018) ---
# One zone set, linked to the hub, shared by every spoke through peering —
# so private endpoints resolve identically estate-wide.
module "private_dns_zones" {
  source   = "Azure/avm-res-network-privatednszone/azurerm"
  version  = "0.3.4"
  for_each = toset(var.private_dns_zones)

  enable_telemetry = false

  domain_name         = each.value
  resource_group_name = var.resource_group_name
  tags                = var.tags

  virtual_network_links = {
    hub = {
      vnetlinkname = "link-${var.virtual_network_name}"
      vnetid       = module.virtual_network.resource_id
    }
  }
}

# --- Azure Monitor Private Link Scope (native resources) ---
# The hard prerequisite the observability substrate's private-by-default
# posture documents: with public ingestion/query off, telemetry only flows
# through an AMPLS. Native azurerm resources — no AVM module wraps AMPLS at
# this pin date, and it is three thin resources (same call as the UAI in
# web-api-aks).
resource "azurerm_monitor_private_link_scope" "this" {
  count = var.create_ampls ? 1 : 0

  name                  = local.ampls_name
  resource_group_name   = var.resource_group_name
  ingestion_access_mode = var.ampls_ingestion_access_mode
  query_access_mode     = var.ampls_query_access_mode
  tags                  = var.tags
}

resource "azurerm_monitor_private_link_scoped_service" "this" {
  for_each = var.create_ampls ? var.ampls_linked_resource_ids : {}

  name                = "amplss-${each.key}"
  resource_group_name = var.resource_group_name
  scope_name          = azurerm_monitor_private_link_scope.this[0].name
  linked_resource_id  = each.value
}

resource "azurerm_private_endpoint" "ampls" {
  count = local.create_ampls_endpoint ? 1 : 0

  name                = local.ampls_private_endpoint_name
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = module.virtual_network.subnets[var.ampls_private_endpoint_subnet_key].resource_id
  tags                = var.tags

  private_service_connection {
    name                           = "ampls"
    private_connection_resource_id = azurerm_monitor_private_link_scope.this[0].id
    is_manual_connection           = false
    subresource_names              = ["azuremonitor"]
  }

  dynamic "private_dns_zone_group" {
    for_each = length(local.ampls_dns_zone_ids) > 0 ? [1] : []
    content {
      name                 = "default"
      private_dns_zone_ids = local.ampls_dns_zone_ids
    }
  }
}
