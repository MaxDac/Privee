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
  name: guid(subscription().id, adminIdentityName, contributorRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', contributorRoleId)
    principalId: adminIdentityModule.outputs.principalId
    principalType: 'ServicePrincipal'
    description: 'GitHub Actions resource management for ${githubRepo} - Contributor role'
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
  ]
  scope: 'Subscription'
  description: 'Resource management access for GitHub Actions deployment (create/delete resources and resource groups)'
}
