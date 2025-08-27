@description('Prefix for resource names (letters/numbers).')
param namePrefix string

@description('Location for all resources.')
param location string = resourceGroup().location

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

// ----------------- Deploy Networking Module -----------------
module networking 'modules/networking.bicep' = {
  params: {
    namePrefix: namePrefix
    location: location
    vnetCidr: vnetCidr
    aksSubnetCidr: aksSubnetCidr
    pgSubnetCidr: pgSubnetCidr
    dnsZoneName: dnsZoneName
    pgServerName: pgServerName
  }
}

// ----------------- Deploy ACR Module -----------------
module acr 'modules/acr.bicep' = {
  params: {
    namePrefix: namePrefix
    location: location
    acrSku: acrSku
  }
}

// ----------------- Deploy PostgreSQL Module -----------------
module postgresql 'modules/postgresql.bicep' = {
  params: {
    pgServerName: pgServerName
    location: location
    pgAdminUser: pgAdminUser
    pgAdminPassword: pgAdminPassword
    pgSubnetId: networking.outputs.pgSubnetId
    pgPrivateDnsZoneId: networking.outputs.pgPrivateDnsZoneId
  }
}

// ----------------- Deploy AKS Module -----------------
module aks 'modules/aks.bicep' = {
  params: {
    namePrefix: namePrefix
    location: location
    aksNodeCount: aksNodeCount
    aksVmSize: aksVmSize
    aksVersion: aksVersion
    aksSubnetId: networking.outputs.aksSubnetId
    acrId: acr.outputs.acrId
  }
}

// ----------------- Outputs -----------------
output aksName string = aks.outputs.aksName
output acrLoginServer string = acr.outputs.acrLoginServer
output dnsZoneId string = networking.outputs.publicDnsZoneId
