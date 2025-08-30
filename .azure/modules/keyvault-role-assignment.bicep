@description('Key Vault name')
param keyVaultName string

@description('Object ID of the principal to assign role to')
param principalObjectId string

@description('Role definition ID to assign')
param roleDefinitionId string

@description('Optional: Human readable role name for better GUID generation')
param roleName string = 'KeyVaultAccess'

// Existing Key Vault in this module's resource group scope
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

// Role assignment scoped to the Key Vault
resource keyVaultPermission 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, roleName, principalObjectId)
  scope: keyVault
  properties: {
    principalId: principalObjectId
    roleDefinitionId: roleDefinitionId
    principalType: 'ServicePrincipal'
  }
}

output roleAssignmentId string = keyVaultPermission.id
