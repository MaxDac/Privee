@description('Prefix for resource names (letters/numbers).')
param namePrefix string

@description('Location for all resources.')
param location string = resourceGroup().location

@description('GitHub organization or user that owns the repo')
param githubOwner string

@description('GitHub repository name')
param githubRepo string

@description('OIDC subject: e.g. ref:refs/heads/main, environment:prod, or pull_request')
param oidcSubject string = 'ref:refs/heads/main'

@description('Resource group name where the ACR lives')
param acrResourceGroup string

@description('ACR name (e.g., Privee)')
param acrName string

@description('Resource group name where the AKS cluster lives')
param aksResourceGroup string

@description('AKS cluster name')
param aksName string

@description('Whether to grant AKS access to the identity.')
param grantAksAccess bool = true

@description('Optionally, provide the AKS kubelet managed identity objectId to attach ACR pull to the cluster (emulates az aks update --attach-acr). Leave empty to skip.')
param aksKubeletIdentityObjectId string = ''

// Azure built-in role definition IDs
var aksClusterUserRoleId = '4abbcc35-e782-43d8-92c5-2d3f1bd2253f' // Azure Kubernetes Service Cluster User Role
var aksRbacClusterAdminRoleId = '3498e952-d568-435e-9b2c-8d77e338d7f7' // Azure Kubernetes Service RBAC Cluster Admin

var uaiName = toLower('${namePrefix}-gha-oidc')
var issuer = 'https://token.actions.githubusercontent.com'
var subject = 'repo:${githubOwner}/${githubRepo}:${oidcSubject}'
var audience = 'api://AzureADTokenExchange'

// ------------- Identity (UAMI) -------------
resource uai 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: uaiName
  location: location
}

// Federated Identity Credential (stable API)
resource fic 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2023-01-31' = {
  name: 'github-oidc'
  parent: uai
  properties: {
    issuer: issuer
    subject: subject
    audiences: [
      audience
    ]
  }
}

// TODO: Remove this before merging the PR
// Federated Identity Credential for the fix branch
resource fic_fix_branch 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2023-01-31' = {
  name: 'github-oidc-fix-branch'
  parent: uai
  dependsOn: [
    fic
  ]
  properties: {
    issuer: issuer
    subject: 'repo:${githubOwner}/${githubRepo}:ref:refs/heads/106-fix-azure-login-1'
    audiences: [
      audience
    ]
  }
}

// ------------- Modules for role assignments (cross-RG safe) -------------
// Note: module paths are relative to this file's directory
module assignAcr './acr-role-assignment.bicep' = {
  name: '${uai.name}-acr-assignments'
  scope: resourceGroup(acrResourceGroup)
  params: {
    acrName: acrName
    principalObjectId: uai.properties.principalId
    principalStableId: uai.id
    kubeletIdentityObjectId: aksKubeletIdentityObjectId
  }
}

module assignAks './aks-rbac-assignment.bicep' = if (grantAksAccess) {
  name: '${uai.name}-aks-rbac'
  scope: resourceGroup(aksResourceGroup)
  params: {
    aksName: aksName
    principalObjectId: uai.properties.principalId
    principalStableId: uai.id
    roleDefinitionId: aksRbacClusterAdminRoleId
  }
}

module assignAksGetCreds './aks-rbac-assignment.bicep' = if (grantAksAccess) {
  name: '${uai.name}-aks-getcreds'
  scope: resourceGroup(aksResourceGroup)
  params: {
    aksName: aksName
    principalObjectId: uai.properties.principalId
    principalStableId: uai.id
    roleDefinitionId: aksClusterUserRoleId
  }
}

// ------------- Outputs -------------
output clientId string = uai.properties.clientId
output principalId string = uai.properties.principalId
output federatedSubject string = subject
