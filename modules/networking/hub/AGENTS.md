# AGENTS.md — networking/hub

AI-agent notes for this module. Read the README first; this file is the sharp edges.

## Scope rules (do not "complete" this module)

- **DO NOT add a firewall, bastion, gateway, or UDRs.** The v0.1 scope is deliberately the already-decided core (ADR 0018); the egress-enforcement surface is deferred until a real estate's requirements exist (issue #9, v0.2). Adding a firewall here without that work is exactly the premature product decision the scoping avoided.
- **DO NOT default `address_space`.** The value is the adopter's addressing plan; a default would be a guess that calcifies (ADR 0018's one-way door).
- The default `private_dns_zones` list is derived from what the shipped modules need. If a new module introduces a private-link dependency, extend the default *and* say which module drives it.

## Implementation notes

- The AVM virtualnetwork module is **azapi-based** and takes `parent_id` (the RG's full resource ID), not `resource_group_name`. We construct the ID from `azurerm_client_config` — that data source is already mocked in tests.
- **`versions.tf` declares `azapi` at the root even though no root resource uses it**: `terraform test`'s `mock_provider` can only bind to root-declared providers, and without it the AVM submodule's azapi calls try real Azure authentication mid-test.
- Test mocks must be **ID-shaped**: azurerm parses the vnet ID (DNS links), subnet ID (private endpoint), and AMPLS ID (private endpoint connection) even under mocks. The contract test's azapi mock defaults to a subnet-shaped ID and overrides the single vnet resource (`override_resource`) with a vnet-shaped one.
- AMPLS uses native `azurerm` resources on purpose — no AVM equivalent at the pin date; three thin resources. Revisit if AVM ships a privatelinkscope module.
- The AMPLS private endpoint's DNS zone group wires whichever of the five Azure Monitor zones this hub actually hosts (`local.ampls_dns_zone_ids` intersection) — removing the monitor zones from `private_dns_zones` silently shrinks that wiring; the contract test pins it at five.

## Validation expectations

CI runs fmt/validate/`terraform test` (13 assertions, both providers mocked, no credentials) plus manifest schema/parity and catalog drift checks. The `rejects_endpoint_subnet_key_not_in_subnets` test depends on the `contains()` guard in `local.create_ampls_endpoint` — if you touch that local, keep the invalid-key path reaching the `terraform_data.input_invariants` precondition rather than an index error.
