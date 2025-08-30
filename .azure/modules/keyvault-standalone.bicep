// Standalone Key Vault deployment template
// This template can be deployed independently at subscription scope
// Deploy: az deployment sub create --location <location> --template-file modules/keyvault-standalone.bicep

targetScope = 'subscription'

@description('Prefix for resource names (letters/numbers).')
param namePrefix string

@description('Location for all resources.')
param location string

@description('Environment name (dev, staging, prod)')
param environment string = 'dev'

@description('Additional tags to apply to resources')
param tags object = {}

var keyVaultResourceGroupName = '${namePrefix}-${environment}-kv-rg'

// ----------------- Create Key Vault Resource Group -----------------
resource keyVaultResourceGroup 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: keyVaultResourceGroupName
  location: location
  tags: union({
    Environment: environment
    Application: 'Privee'
    Component: 'KeyVault'
    ManagedBy: 'Bicep'
  }, tags)
}

// ----------------- Deploy Key Vault Module -----------------
module keyVaultModule 'keyvault.bicep' = {
  name: 'keyVault-deployment'
  scope: az.resourceGroup(subscription().subscriptionId, keyVaultResourceGroupName)
  dependsOn: [
    keyVaultResourceGroup
  ]
  params: {
    namePrefix: namePrefix
    location: location
    resourceGroupName: keyVaultResourceGroupName
  }
}

// ----------------- Outputs -----------------
output keyVaultResourceGroupName string = keyVaultResourceGroup.name
output keyVaultName string = keyVaultModule.outputs.keyVaultName
output keyVaultId string = keyVaultModule.outputs.keyVaultId
