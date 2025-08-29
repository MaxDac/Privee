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

@description('Optional DNS Zone resource ID for app routing add-on. Leave empty to enable the add-on without Azure DNS integration.')
param dnsZoneId string = ''

var aksName = '${namePrefix}-aks'

@description('Enable autoscaling for the AKS agent pool (recommended). If disabled, a minimum of 2 nodes will be enforced.')
param enableAutoScaling bool = false

@description('Minimum node count when autoscaling is enabled (will be enforced to be at least 2).')
param minNodeCount int = 2

@description('Maximum node count when autoscaling is enabled.')
param maxNodeCount int = 3

// Enforce a minimum capacity of 2 nodes for HA and at least 2 replicas capacity
var effectiveMinCount = max(minNodeCount, 2)
var effectiveNodeCount = max(aksNodeCount, 2)

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
        // When autoscaling is enabled, omit count and set min/max; otherwise enforce a minimum of 2 nodes
        count: enableAutoScaling ? null : effectiveNodeCount
        enableAutoScaling: enableAutoScaling
        minCount: enableAutoScaling ? effectiveMinCount : null
        maxCount: enableAutoScaling ? maxNodeCount : null
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
    // Enable Web Application Routing add-on. If a DNS zone is provided, integrate with Azure DNS; otherwise, use the add-on without DNS integration.
    ingressProfile: {
      webAppRouting: empty(dnsZoneId)
        ? {
            enabled: true
          }
        : {
            enabled: true
            dnsZoneResourceIds: [dnsZoneId]
          }
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

// Grant the Web Application Routing add-on permissions to manage DNS records (only when a DNS zone is provided)
var dnsZoneContributorRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'befefa01-2a29-4197-83a8-272ff33ce314')

resource dnsPermission 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(dnsZoneId)) {
  name: guid(dnsZoneId, 'dns-contributor', aks.name)
  scope: resourceGroup()
  properties: {
    principalId: aks.properties.ingressProfile.webAppRouting.identity.objectId
    roleDefinitionId: dnsZoneContributorRoleId
    principalType: 'ServicePrincipal'
  }
}

// ----------------- Outputs -----------------
output aksId string = aks.id
output aksName string = aks.name
output aksPrincipalId string = aks.identity.principalId
output aksKubeletPrincipalId string = aks.properties.identityProfile.kubeletidentity.objectId
output webAppRoutingIdentityObjectId string = aks.properties.ingressProfile.webAppRouting.identity.objectId
