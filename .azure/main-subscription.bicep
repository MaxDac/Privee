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

@description('Optional subdomain label to create and delegate as a child DNS zone (e.g., "app"). If provided, AKS will use the child zone for Web App Routing.')
param subdomainLabel string = ''

@secure()
@description('CosmosDB admin password')
param cosmosAdminPassword string

@description('VNet CIDR')
param vnetCidr string = '10.0.0.0/16'

@description('AKS subnet CIDR')
param aksSubnetCidr string = '10.0.1.0/24'

@description('Additional tags to apply to resources')
param tags object = {}

@description('Optional DNS label to assign to the web app routing public IP (cloudapp.azure.com). Leave empty to skip.')
param ingressDnsLabel string = ''

@description('Key Vault resource ID (must be deployed separately first)')
param keyVaultId string

@description('Optional explicit Public IP resource name in the AKS node resource group to update with the DNS label. If empty, the module will auto-select.')
param ingressPublicIpName string = ''

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
    subdomainLabel: subdomainLabel
    cosmosAdminPassword: cosmosAdminPassword
    vnetCidr: vnetCidr
    aksSubnetCidr: aksSubnetCidr
    keyVaultId: keyVaultId // Key Vault ID should be provided as parameter
    ingressDnsLabel: ingressDnsLabel
    ingressPublicIpName: ingressPublicIpName
  }
}

// ----------------- Outputs -----------------
output mainResourceGroupName string = resourceGroups.outputs.mainResourceGroupName
output keyVaultResourceGroupName string = resourceGroups.outputs.keyVaultResourceGroupName
output aksName string = infrastructure.outputs.aksName
output dnsZoneId string = infrastructure.outputs.dnsZoneId
output ingressFqdn string = infrastructure.outputs.ingressFqdn

// Keep backward compatibility
output resourceGroupName string = resourceGroups.outputs.mainResourceGroupName
