module "naming" {
  source = "../.."

  org      = "wsx"
  workload = "memberapi"
  env      = "prod"
  region   = "westus2"
  instance = "03"
}

output "names" {
  value = module.naming.names
}

output "region_abbr" {
  value = module.naming.region_abbr
}

output "parts" {
  value = module.naming.parts
}
