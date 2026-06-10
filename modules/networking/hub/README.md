# networking/hub

The hub network's **decided core**: the hub VNet every spoke peers to, the centralized private DNS zones that make private endpoints resolve identically estate-wide, and the **Azure Monitor Private Link Scope (AMPLS)** — the hard prerequisite the observability substrate's private-by-default posture documents.

This is a deliberately scoped v0.1 of [ADR 0018](../../../docs/decisions/0018-network-topology-hub-spoke.md). It builds only what that decision already settled; everything that would force a premature product choice is deferred — see "What this module does NOT build" below.

## What ships

| Resource | Via | Why |
|---|---|---|
| Hub VNet + subnets | AVM `avm-res-network-virtualnetwork` | The shared-services network and spoke peering surface (ADR 0018). |
| Private DNS zones, linked to the hub | AVM `avm-res-network-privatednszone` | Centralized resolution: one zone set shared by every spoke, so `privatelink.*` names resolve the same everywhere. |
| AMPLS + scoped services + optional private endpoint | native `azurerm` resources | Wires Azure Monitor onto the private network. No AVM module wraps AMPLS at this pin date, and it is three thin resources — the same call as the UAI in `web-api-aks`. |

The **default DNS zone list isn't a guess** — it's exactly the set the shipped modules require: `privatelink.vaultcore.azure.net` for Key Vault private endpoints (`web-api-aks`) and the five Azure Monitor zones the AMPLS resolves through.

## Inputs (the load-bearing ones)

| Name | Required | Description |
|---|---|---|
| `virtual_network_name` | yes | From `foundation/naming`. |
| `resource_group_name`, `location` | yes | The consumer owns the RG (ADR 0004). |
| `address_space` | yes | **No default on purpose.** The value is the adopter's addressing plan — centrally assigned, non-overlapping, written down. Re-numbering a live network is the truest one-way door in the design (ADR 0018). |
| `subnets` | no | Map keyed by subnet name. Declare a private-endpoints subnet; firewall/gateway subnets belong to v0.2. |
| `private_dns_zones` | no | Defaults to the six zones the shipped modules need. |
| `create_ampls` | no | Default `true`. Disable only when the estate already operates an AMPLS. |
| `ampls_linked_resource_ids` | no | **The seam that matters:** pass the substrate's `log_analytics_workspace_id` and `application_insights_id` here, and its private-by-default posture starts actually working. |
| `ampls_private_endpoint_subnet_key` | no | Names the subnet hosting the AMPLS endpoint; null skips it. |
| `ampls_ingestion_access_mode` / `ampls_query_access_mode` | no | `PrivateOnly` by default (ADR 0018 default-deny). `Open` is the documented escape hatch for estates mid-migration. |

## Outputs

The non-firewall half of the [ADR 0018 §6](../../../docs/decisions/0018-network-topology-hub-spoke.md) contract: `virtual_network_id` (the spoke peering surface), `subnet_ids`, `private_dns_zone_ids` (feed these to workload patterns' `private_endpoints` inputs), `address_space`, `ampls_id`, `ampls_private_endpoint_id`. The firewall surface — firewall private IP, route-table IDs — ships with v0.2.

## Composition

```hcl
module "hub" {
  source = "../../modules/networking/hub"

  virtual_network_name = module.naming.names.virtual_network
  resource_group_name  = azurerm_resource_group.platform.name
  location             = var.location
  tags                 = module.tags.tags
  address_space        = var.hub_address_space # the adopter's plan, not ours

  subnets = { private-endpoints = { address_prefixes = var.hub_private_endpoint_prefixes } }

  ampls_linked_resource_ids = {
    law  = module.observability_substrate.log_analytics_workspace_id
    appi = module.observability_substrate.application_insights_id
  }
  ampls_private_endpoint_subnet_key = "private-endpoints"
}
```

Spoke peering happens at the consumer boundary (ADR 0004): a spoke root takes `virtual_network_id` and creates both peering halves itself. There is no spoke module yet — `examples/workload-onboarding` shows consumption, and a spoke wrapper waits for a second consumer.

## What this module does NOT build (and why)

- **The firewall.** Product (Azure Firewall vs. NVA), SKU tier, and rule-engine shape are decisions that would be made blind today and reversed when a real estate's egress requirements and budget exist. Until it ships, default-deny egress (ADR 0018 §2) is **not enforced** — the control map declares this honestly as the `csf:PR.AC-5` gap. *Trigger to build:* an estate with real egress requirements, or the ADR 0018 v0.2 work picking up issue #9's remaining scope.
- **Bastion, VPN/ExpressRoute gateways, forced-tunneling UDRs.** Same category: real-world-dependent product choices.
- **Spoke VNets.** Consumer-boundary work until a second consumer proves the wrapper's shape.

## Why this module ships no `policy/` or `monitoring/`

Its resources are network plumbing whose governance arrives with the v0.2 egress work (deny-public-IP, require-UDR policies belong with the firewall they protect); DNS and AMPLS health surface through the substrate's platform diagnostics. The empty `ships` arrays in `manifest.yaml` reflect this; per [ADR 0003](../../../docs/decisions/0003-modules-ship-policy-and-monitoring.md), missing-because-not-applicable is stated, not implied.

## Cites

- Implements [ADR 0018](../../../docs/decisions/0018-network-topology-hub-spoke.md) (the decided core: hub, central DNS, the addressing discipline) and the non-firewall half of its §6 output contract.
- Implements [ADR 0001](../../../docs/decisions/0001-iac-terraform-with-avm.md) (AVM-first; native resources only where AVM has no equivalent).
- Honors [ADR 0004](../../../docs/decisions/0004-composition-by-output-data.md) (peering and spoke wiring at the consumer boundary).
- Serves [ADR 0005](../../../docs/decisions/0005-observability-substrate-and-signal-parity.md) (the AMPLS is what makes the substrate's private posture operable).
- Prevents [AP-003 (hard-coded service endpoints)](../../../docs/anti-patterns.md#ap-003--hard-coded-service-endpoints) — centralized private DNS instead of per-service hand-managed addressing.
