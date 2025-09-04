// Base infrastructure deployment template
// This template creates the foundational User Managed Identity for GitHub Actions
// with administrative permissions over the subscription for resource deployment and management
//
// Deploy at subscription scope:
// az deployment sub create --location <location> --template-file admin-identity.bicep --parameters @admin-identity.parameters.json

targetScope = 'subscription'

@description('Prefix for resource names (letters/numbers only).')
param namePrefix string

@description('Location for all resources.')
param location string

@description('GitHub organization or user that owns the repository')
param githubOwner string

@description('GitHub repository name')
param githubRepo string

@description('OIDC subject for GitHub Actions authentication (e.g., ref:refs/heads/main)')
param oidcSubject string = 'ref:refs/heads/main'

@description('Environment name (dev, staging, prod)')
param environment string = 'dev'

@description('Resource group name for the identity resources')
param identityResourceGroupName string = '${namePrefix}-identity-rg'

// Azure built-in role definition IDs for administrative access
var contributorRoleId = 'b24988ac-6180-42a0-ab88-20f7382dd24c' // Contributor role

// Custom role for minimal role assignment permissions
var minimalRoleAssignerRoleName = '${namePrefix}-minimal-role-assigner-${environment}'
var minimalRoleAssignerRoleId = guid(subscription().id, minimalRoleAssignerRoleName)

// Identity configuration
var adminIdentityName = toLower('${namePrefix}-gha-admin-${environment}')

// ------------- Resource Group for Identity -------------
resource identityResourceGroup 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: identityResourceGroupName
  location: location
  tags: {
    Purpose: 'GitHub Actions Identity'
    Environment: environment
    ManagedBy: 'Bicep'
  }
}

// ------------- Deploy Identity via Module -------------
module adminIdentityModule 'identity.bicep' = {
  name: 'admin-identity-deployment'
  scope: identityResourceGroup
  params: {
    identityName: adminIdentityName
    location: location
    githubOwner: githubOwner
    githubRepo: githubRepo
    oidcSubject: oidcSubject
    environment: environment
  }
}

// ------------- Subscription-level Role Assignments -------------
// Contributor role assignment for resource management access
resource contributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, adminIdentityName, contributorRoleId, 'contributor')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', contributorRoleId)
    principalId: adminIdentityModule.outputs.principalId
    principalType: 'ServicePrincipal'
    description: 'GitHub Actions resource management for ${githubRepo} - Contributor role'
  }
}

// Get the existing custom role definition (it should exist from previous deployment)
resource existingMinimalRoleAssignerRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  name: minimalRoleAssignerRoleId
}

// Minimal role assignment permission for creating role assignments
resource minimalRoleAssignerRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, adminIdentityName, minimalRoleAssignerRoleId, 'minimal-role')
  properties: {
    roleDefinitionId: existingMinimalRoleAssignerRole.id
    principalId: adminIdentityModule.outputs.principalId
    principalType: 'ServicePrincipal'
    description: 'GitHub Actions minimal role assignment permission for ${githubRepo} - Custom role for Microsoft.Authorization/roleAssignments/write'
  }
}

// ------------- Outputs -------------
@description('The Client ID of the User Managed Identity for GitHub Actions secrets')
output clientId string = adminIdentityModule.outputs.clientId

@description('The Principal ID of the User Managed Identity')
output principalId string = adminIdentityModule.outputs.principalId

@description('The Resource ID of the User Managed Identity')
output identityResourceId string = adminIdentityModule.outputs.identityResourceId

@description('The name of the created resource group')
output resourceGroupName string = identityResourceGroup.name

@description('The federated identity subject used for OIDC')
output federatedSubject string = adminIdentityModule.outputs.federatedSubject

@description('Summary of permissions granted')
output permissionsSummary object = {
  subscription: subscription().subscriptionId
  roles: [
    'Contributor' // Full resource management without access control
    'Custom: Minimal Role Assigner' // Only Microsoft.Authorization/roleAssignments/write permission
  ]
  scope: 'Subscription'
  description: 'Resource management access + minimal role assignment permission to fix Microsoft.Authorization/roleAssignments/write error'
  customRoleNote: 'Custom role provides only the specific permission mentioned in the error: Microsoft.Authorization/roleAssignments/write'
}
