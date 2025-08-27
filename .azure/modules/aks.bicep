@description('Prefix for resource names (letters/numbers).')
param namePrefix string

@description('Location for all resources.')
param location string = resourceGroup().location

@description('AKS node count')
param aksNodeCount int = 3

@description('AKS VM size')
param aksVmSize string = 'Standard_D4s_v5'

@description('AKS Kubernetes version (optional). Leave empty for default).')
param aksVersion string = ''

@description('AKS subnet resource ID')
param aksSubnetId string

@description('ACR resource ID for role assignment')
param acrId string

var aksName = '${namePrefix}-aks'

// ----------------- AKS -----------------
resource aks 'Microsoft.ContainerService/managedClusters@2024-05-01' = {
  name: aksName
  location: location
  identity: { type: 'SystemAssigned' }
  sku: { name: 'Base', tier: 'Standard' }
  properties: {
    dnsPrefix: '${namePrefix}-aks'
    kubernetesVersion: empty(aksVersion) ? null : aksVersion
    agentPoolProfiles: [
      {
        name: 'systempool'
        count: aksNodeCount
        vmSize: aksVmSize
        osType: 'Linux'
        mode: 'System'
        vnetSubnetID: aksSubnetId
      }
    ]
    networkProfile: {
      networkPlugin: 'azure'
      networkPluginMode: 'overlay' // Azure CNI Overlay simplifies IP planning and NATs egress to VNet
      loadBalancerSku: 'standard'
      serviceCidr: '10.1.0.0/16'
      dnsServiceIP: '10.1.0.10'
    }
  }
}

// Allow AKS kubelet identity to pull from ACR (assign AcrPull at registry scope)
var acrPullRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions','7f951dda-4ed3-4680-a7ca-43fe172d538d')

resource existingAcr 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: split(acrId, '/')[8]
}

resource acrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acrId, 'AcrPull', aks.name)
  scope: existingAcr
  properties: {
    principalId: aks.properties.identityProfile.kubeletidentity.objectId
    roleDefinitionId: acrPullRoleId
    principalType: 'ServicePrincipal'
  }
}

// ----------------- Outputs -----------------
output aksId string = aks.id
output aksName string = aks.name
output aksPrincipalId string = aks.identity.principalId
output aksKubeletPrincipalId string = aks.properties.identityProfile.kubeletidentity.objectId
