@description('Prefix for resource names (letters/numbers).')
param namePrefix string

@description('Location for all resources.')
param location string

@description('Resource group name where Key Vault should be deployed.')
param resourceGroupName string

var keyVaultName = '${namePrefix}-kv'

// Target scope will be set when calling this module
targetScope = 'resourceGroup'

// ----------------- Key Vault (for TLS certs) -----------------
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  properties: {
    enableSoftDelete: true
    enablePurgeProtection: true // Required by Azure - cannot be set to false
    enableRbacAuthorization: true // AKS add-on uses RBAC role assignment when attached
    tenantId: subscription().tenantId
    sku: { name: 'standard', family: 'A' }
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
  }
}

// ----------------- Outputs -----------------
output keyVaultId string = keyVault.id
output keyVaultName string = keyVault.name
output keyVaultResourceGroup string = resourceGroupName
