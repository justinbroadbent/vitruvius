terraform {
  required_version = ">= 1.7.0"
}

# Smallest sane invocation: just the tag map. No policy deployment.
# Use this shape when a workload-pattern module needs the canonical tag map but
# the policy initiative is owned at a higher scope (and assigned once, not
# per-workload).

module "tags" {
  source = "../.."

  owner                = "platform-team"
  env                  = "dev"
  cost_center          = "cc-1001"
  data_classification  = "internal"
  business_criticality = "tier-2"
}

output "tags" {
  value = module.tags.tags
}
