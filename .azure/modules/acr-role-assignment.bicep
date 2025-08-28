@description('ACR name')
param acrName string

@description('Object ID of the principal to assign AcrPush to (e.g., UAMI principalId)')
param principalObjectId string

@description('A stable, compile-time ID to build name deterministically (e.g., UAMI resourceId)')
param principalStableId string

@description('Optional kubelet identity objectId to grant AcrPull (attach-acr equivalent). Leave empty to skip.')
@secure()
param kubeletIdentityObjectId string = ''

// Built-in role IDs
var acrPushRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '8311e382-0749-4cb8-b61a-304f252e45ec') // AcrPush
var acrPullRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d') // AcrPull

// Existing ACR in this module's RG scope
resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: acrName
}

// AcrPush to CI principal
resource acrPush 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, 'acr-push', principalStableId)
  scope: acr
  properties: {
    roleDefinitionId: acrPushRoleId
    principalId: principalObjectId
    principalType: 'ServicePrincipal'
  }
}

// Optional: AcrPull to kubelet identity
resource acrPullForKubelet 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(kubeletIdentityObjectId)) {
  name: guid(acr.id, 'acr-pull-kubelet', kubeletIdentityObjectId)
  scope: acr
  properties: {
    roleDefinitionId: acrPullRoleId
    principalId: kubeletIdentityObjectId
    principalType: 'ServicePrincipal'
  }
}