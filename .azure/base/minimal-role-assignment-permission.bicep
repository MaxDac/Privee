// Minimal role assignment permission template
// This template creates a custom role with only the specific permission needed for role assignments
// Deploy at subscription scope before admin-identity.bicep

targetScope = 'subscription'

@description('Prefix for resource names')
param namePrefix string

@description('Environment name (dev, staging, prod)')
param environment string = 'dev'

// Custom role configuration with minimal permissions
var customRoleName = '${namePrefix}-minimal-role-assigner-${environment}'
var customRoleDescription = 'Minimal custom role that allows only creating role assignments - addresses Microsoft.Authorization/roleAssignments/write permission error'

// Create custom role definition with minimal role assignment permissions
resource minimalRoleAssignerRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' = {
  name: guid(subscription().id, customRoleName)
  properties: {
    roleName: customRoleName
    description: customRoleDescription
    type: 'CustomRole'
    assignableScopes: [
      subscription().id
    ]
    permissions: [
      {
        actions: [
          // Only the specific permission mentioned in the error
          'Microsoft.Authorization/roleAssignments/write'
          'Microsoft.Authorization/roleAssignments/read'
          'Microsoft.Authorization/roleDefinitions/read'
        ]
        notActions: []
        dataActions: []
        notDataActions: []
      }
    ]
  }
}

// Outputs
output customRoleDefinitionId string = minimalRoleAssignerRole.id
output customRoleName string = customRoleName
output roleDefinitionGuid string = guid(subscription().id, customRoleName)
output description string = customRoleDescription
