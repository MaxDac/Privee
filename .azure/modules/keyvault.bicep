@description('Prefix for resource names (letters/numbers).')
param namePrefix string

@description('Location for all resources.')
param location string

var keyVaultName = '${namePrefix}-${uniqueString(resourceGroup().id)}-kv'

// ----------------- Key Vault (for TLS certs) -----------------
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  properties: {
    enableSoftDelete: true
    enablePurgeProtection: false // Only for Dev
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
