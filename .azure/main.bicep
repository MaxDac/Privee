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

@description('Optional subdomain label to create and delegate as a child DNS zone (e.g., "app"). If provided, AKS will use the child zone for Web App Routing.')
param subdomainLabel string = ''

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

// Add Key Vault ID parameter
@description('Key Vault resource ID for app routing add-on')
param keyVaultId string

@description('Optional DNS label to assign to the web app routing public IP (cloudapp.azure.com). Leave empty to skip.')
param ingressDnsLabel string = ''

@description('Optional explicit Public IP resource name in the AKS node resource group to update with the DNS label. If empty, the module will auto-select.')
param ingressPublicIpName string = ''

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
  subdomainLabel: subdomainLabel
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
  name: 'aks'
  params: {
    namePrefix: namePrefix
    location: location
    aksNodeCount: aksNodeCount
    aksVmSize: aksVmSize
    aksVersion: aksVersion
    aksSubnetId: networking.outputs.aksSubnetId
    acrId: acr.outputs.acrId
    dnsZoneId: networking.outputs.publicDnsZoneId
  }
}

// Optionally set the Public IP DNS label for the ingress controller in the AKS node resource group
module ingressDns 'modules/ingress-dnslabel.bicep' = if (!empty(ingressDnsLabel)) {
  name: 'ingress-dnslabel'
  // Node resource group name is deterministic: MC_{mainRG}_{aksName}_{location}
  scope: az.resourceGroup(subscription().subscriptionId, 'MC_${resourceGroup().name}_${namePrefix}-aks_${location}')
  dependsOn: [ aks ]
  params: {
    namePrefix: namePrefix
    location: location
    ingressDnsLabel: ingressDnsLabel
    ingressPublicIpName: ingressPublicIpName
  }
}

// ----------------- Grant AKS Web App Routing access to Key Vault -----------------
var keyVaultSecretsUserRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')
var keyVaultName = split(keyVaultId, '/')[8]
var keyVaultResourceGroupName = split(keyVaultId, '/')[4]

module aksKeyVaultAccess 'modules/keyvault-role-assignment.bicep' = {
  name: 'aks-keyvault-access'
  scope: resourceGroup(keyVaultResourceGroupName)
  params: {
    keyVaultName: keyVaultName
    principalObjectId: aks.outputs.webAppRoutingIdentityObjectId
    roleDefinitionId: keyVaultSecretsUserRoleId
    roleName: 'SecretsUser'
  }
}

// ----------------- Outputs -----------------
output aksName string = aks.outputs.aksName
output acrLoginServer string = acr.outputs.acrLoginServer
output dnsZoneId string = networking.outputs.publicDnsZoneId

// Ingress FQDN output (conditional on ingressDnsLabel being set)
output ingressFqdn string = !empty(ingressDnsLabel) ? '${ingressDnsLabel}.${location}.cloudapp.azure.com' : ''
