@description('AKS cluster name')
param aksName string

@description('Object ID of the principal to assign RBAC to (e.g., UAMI principalId)')
param principalObjectId string

@description('Stable, compile-time ID to build name deterministically (e.g., UAMI resourceId)')
param principalStableId string

@description('Role definition ID for AKS (e.g., Azure Kubernetes Service RBAC Cluster Admin)')
param roleDefinitionId string

// Existing AKS in this module's RG scope
resource aks 'Microsoft.ContainerService/managedClusters@2024-02-01' existing = {
  name: aksName
}

resource aksRbac 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aks.id, 'aks-rbac', principalStableId)
  scope: aks
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionId)
    principalId: principalObjectId
    principalType: 'ServicePrincipal'
  }
}