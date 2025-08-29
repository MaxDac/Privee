// This template deploys the entire infrastructure including resource group
// Deploy at subscription scope: az deployment sub create --location <location> --template-file main-subscription.bicep

targetScope = 'subscription'

@description('Prefix for resource names (letters/numbers).')
param namePrefix string

@description('Location for all resources.')
param location string

@description('Environment name (dev, staging, prod)')
param environment string = 'dev'

@allowed(['Basic','Standard','Premium'])
@description('SKU for Azure Container Registry.')
param acrSku string = 'Standard'

@description('AKS node count')
param aksNodeCount int = 3

@description('AKS VM size')
param aksVmSize string = 'Standard_D4s_v5'

@description('AKS Kubernetes version (optional). Leave empty for default).')
param aksVersion string = ''

@description('Public Azure DNS zone to host your app domain (e.g., example.com).')
param dnsZoneName string

@description('PostgreSQL server name (globally unique).')
param pgServerName string = '${namePrefix}pg'

@description('PostgreSQL admin user')
param pgAdminUser string = 'pgadmin'

@secure()
@description('PostgreSQL admin password')
param pgAdminPassword string

@description('VNet CIDR')
param vnetCidr string = '10.0.0.0/16'

@description('AKS subnet CIDR')
param aksSubnetCidr string = '10.0.1.0/24'

@description('PostgreSQL delegated subnet CIDR')
param pgSubnetCidr string = '10.0.2.0/24'

@description('Additional tags to apply to resources')
param tags object = {}

// ----------------- Deploy Resource Groups Modules -----------------
module resourceGroups 'modules/resourcegroups.bicep' = {
  name: 'resourceGroups-deployment'
  params: {
    namePrefix: namePrefix
    location: location
    environment: environment
    tags: tags
  }
}

// ----------------- Deploy Key Vault in separate Resource Group -----------------
module keyVault 'modules/keyvault.bicep' = {
  name: 'keyVault-deployment'
  scope: az.resourceGroup(subscription().subscriptionId, '${namePrefix}-${environment}-kv-rg')
  dependsOn: [
    resourceGroups
  ]
  params: {
    namePrefix: namePrefix
    location: location
    resourceGroupName: '${namePrefix}-${environment}-kv-rg'
  }
}

// ----------------- Deploy Infrastructure within Main Resource Group -----------------
module infrastructure 'main.bicep' = {
  name: 'infrastructure-deployment'
  scope: az.resourceGroup(subscription().subscriptionId, '${namePrefix}-${environment}-rg')
  dependsOn: [
    resourceGroups
  ]
  params: {
    namePrefix: namePrefix
    location: location
    acrSku: acrSku
    aksNodeCount: aksNodeCount
    aksVmSize: aksVmSize
    aksVersion: aksVersion
    dnsZoneName: dnsZoneName
    pgServerName: pgServerName
    pgAdminUser: pgAdminUser
    pgAdminPassword: pgAdminPassword
    vnetCidr: vnetCidr
    aksSubnetCidr: aksSubnetCidr
    pgSubnetCidr: pgSubnetCidr
    keyVaultId: keyVault.outputs.keyVaultId // Pass Key Vault ID
  }
}

// ----------------- Outputs -----------------
output mainResourceGroupName string = resourceGroups.outputs.mainResourceGroupName
output keyVaultResourceGroupName string = resourceGroups.outputs.keyVaultResourceGroupName
output aksName string = infrastructure.outputs.aksName
output keyVaultName string = keyVault.outputs.keyVaultName
output keyVaultId string = keyVault.outputs.keyVaultId
output dnsZoneId string = infrastructure.outputs.dnsZoneId

// Keep backward compatibility
output resourceGroupName string = resourceGroups.outputs.mainResourceGroupName
