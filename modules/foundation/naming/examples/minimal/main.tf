module "naming" {
  source = "../.."

  org      = "wsx"
  workload = "demo"
  env      = "dev"
  region   = "eastus"
}

output "names" {
  value = module.naming.names
}
