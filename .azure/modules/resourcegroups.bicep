@description('Prefix for resource names (letters/numbers).')
param namePrefix string

@description('Location for all resources.')
param location string

@description('Environment name (dev, staging, prod)')
param environment string = 'dev'

@description('Additional tags to apply to the resource group')
param tags object = {}

var resourceGroupName = '${namePrefix}-${environment}-rg'

// Note: This template should be deployed at subscription scope
// to create the resource group
targetScope = 'subscription'

// Create the resource group with standard tags
resource resourceGroup 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: resourceGroupName
  location: location
  tags: union({
    Environment: environment
    Application: 'Privee'
    ManagedBy: 'Bicep'
  }, tags)
}

// ----------------- Outputs -----------------
output resourceGroupName string = resourceGroup.name
output resourceGroupId string = resourceGroup.id
output location string = resourceGroup.location
