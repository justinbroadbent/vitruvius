output "deploy" {
  value = {
    id           = azurerm_user_assigned_identity.deploy.id
    principal_id = azurerm_user_assigned_identity.deploy.principal_id
    client_id    = azurerm_user_assigned_identity.deploy.client_id
    tenant_id    = azurerm_user_assigned_identity.deploy.tenant_id
    name         = azurerm_user_assigned_identity.deploy.name
  }
  description = "Platform deploy UAI. The identity CI/CD assumes when applying platform Terraform. Consumers grant role assignments at the appropriate scope."
}

output "policy_remediation" {
  value = {
    id           = azurerm_user_assigned_identity.policy_remediation.id
    principal_id = azurerm_user_assigned_identity.policy_remediation.principal_id
    client_id    = azurerm_user_assigned_identity.policy_remediation.client_id
    tenant_id    = azurerm_user_assigned_identity.policy_remediation.tenant_id
    name         = azurerm_user_assigned_identity.policy_remediation.name
  }
  description = "Platform policy-remediation UAI. Available for Azure Policy assignments using DeployIfNotExists or Modify effects. Consumers grant role assignments per the resource types each policy needs to remediate."
}
