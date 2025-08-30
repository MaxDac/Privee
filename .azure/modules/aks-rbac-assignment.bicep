@description('AKS cluster name')
param aksName string

@description('Object ID of the principal to assign RBAC to (e.g., UAMI principalId or federated OIDC MI)')
param principalObjectId string

@description('Role definition ID for AKS (e.g., Azure Kubernetes Service RBAC Cluster Admin or Cluster User Role)')
param roleDefinitionId string

@description('Optional: Human readable role name for better GUID generation')
param roleName string = roleDefinitionId

// Existing AKS in this module's RG scope
resource aks 'Microsoft.ContainerService/managedClusters@2024-02-01' existing = {
  name: aksName
}

// Role assignment based on the provided role definition ID
resource aksRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid('${aks.id}-${roleName}-${principalObjectId}')
  scope: aks
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionId)
    principalId: principalObjectId
    principalType: 'ServicePrincipal'
  }
}
