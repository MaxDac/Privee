@description('ACR name')
param acrName string

@description('Principal object ID to assign the role to')
param principalObjectId string

@description('Role definition ID for the custom ACR build role')
param roleDefinitionId string

// Existing ACR in this module's RG scope
resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: acrName
}

// Assign the custom ACR Build role at the registry scope
resource acrBuildUploadRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid('${acr.id}-acr-build-upload-${principalObjectId}')
  scope: acr
  properties: {
    roleDefinitionId: roleDefinitionId
    principalId: principalObjectId
    principalType: 'ServicePrincipal'
  }
}
