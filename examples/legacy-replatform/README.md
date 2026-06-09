# examples/legacy-replatform

The migration story: vendor BPM (business process management) and data platforms moved from on-prem or vendor-hosted infrastructure to Azure-native equivalents. The example demonstrates the shape of a "lift, then shift, then idiomatic" migration that preserves audit and observability throughout.

**Status: deferred.**

What this example will eventually demonstrate:

- Phased migration: lift-and-shift (existing VMs → Azure VMs), then refactor (VMs → AKS or App Service), then idiomatic (workload pattern adoption).
- Substrate continuity — observability follows the workload across phases; auditors don't lose visibility during the migration.
- Tag taxonomy compliance from day one of the lift, even if the workload's underlying shape is still legacy.
- Decommissioning evidence — proving the source system was retired, not just abandoned.

What's blocking:

- The choice of legacy system to model. The adopter's real systems are likely to differ from the generic example shape; modeling a specific real one is more useful than modeling an abstract one.
- The phasing decisions (how aggressive is "phase 2 → phase 3" promotion) depend on team capacity and risk appetite, not platform-team unilateral choice.

When the build starts, the example documents the migration **pattern**, not a specific vendor's product. The pattern is the reusable artifact; the vendor specifics are environment-specific and live in that environment's runbook, not in this repo.
