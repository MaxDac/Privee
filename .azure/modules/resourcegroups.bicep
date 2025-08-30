@description('Prefix for resource names (letters/numbers).')
param namePrefix string

@description('Location for all resources.')
param location string

@description('Environment name (dev, staging, prod)')
param environment string = 'dev'

@description('Additional tags to apply to the resource group')
param tags object = {}

var mainResourceGroupName = '${namePrefix}-${environment}-rg'
var keyVaultResourceGroupName = '${namePrefix}-${environment}-kv-rg'

// Note: This template should be deployed at subscription scope
// to create the resource groups
targetScope = 'subscription'

// Create the main resource group with standard tags
resource mainResourceGroup 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: mainResourceGroupName
  location: location
  tags: union({
    Environment: environment
    Application: 'Privee'
    ManagedBy: 'Bicep'
  }, tags)
}

// Create the Key Vault resource group with standard tags
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

// ----------------- Outputs -----------------
output mainResourceGroupName string = mainResourceGroup.name
output mainResourceGroupId string = mainResourceGroup.id
output keyVaultResourceGroupName string = keyVaultResourceGroup.name
output keyVaultResourceGroupId string = keyVaultResourceGroup.id
output location string = mainResourceGroup.location

// Keep backward compatibility
output resourceGroupName string = mainResourceGroup.name
output resourceGroupId string = mainResourceGroup.id
