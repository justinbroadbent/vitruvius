terraform {
  required_version = ">= 1.14.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.46.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# Full invocation: every tunable supplied — a pinned Kubernetes version, an
# autoscaling system pool, a BYO control-plane identity, the hub's private DNS
# zone for the private API server, and an API-server IP allow-list. The security
# posture is still fixed by the module.

module "naming" {
  source = "../../../../foundation/naming"

  org      = "wsx"
  workload = "platform"
  env      = "prod"
  region   = "eastus"
}

module "tags" {
  source = "../../../../foundation/tags"

  owner                = "platform-team"
  env                  = "prod"
  cost_center          = "cc-1000"
  data_classification  = "confidential"
  business_criticality = "tier-0"

  app             = "platform"
  component       = "core"
  lifecycle_stage = "stable"
}

module "aks" {
  source = "../.."

  name                       = module.naming.names.aks_cluster
  resource_group_id          = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-platform-prod"
  location                   = "eastus"
  node_subnet_id             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub-prod/providers/Microsoft.Network/virtualNetworks/vnet-hub-prod/subnets/snet-aks"
  log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-platform-prod/providers/Microsoft.OperationalInsights/workspaces/log-platform-prod"
  admin_group_object_ids     = ["11111111-1111-1111-1111-111111111111", "22222222-2222-2222-2222-222222222222"]
  tags                       = module.tags.tags

  kubernetes_version = "1.30"

  system_node_pool = {
    vm_size         = "Standard_D8s_v5"
    node_count      = 3
    min_count       = 3
    max_count       = 6
    os_disk_size_gb = 256
  }

  network = {
    network_policy = "cilium"
    service_cidr   = "172.16.0.0/16"
    dns_service_ip = "172.16.0.10"
    pod_cidr       = "10.244.0.0/16"
  }

  private_dns_zone_id       = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub-prod/providers/Microsoft.Network/privateDnsZones/privatelink.eastus.azmk8s.io"
  authorized_ip_ranges      = ["10.0.0.0/8"]
  user_assigned_identity_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-platform-prod/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-aks-cp"
  upgrade_channel           = "patch"
}

output "oidc_issuer_url" {
  value = module.aks.oidc_issuer_url
}

output "cluster_id" {
  value = module.aks.cluster_id
}
