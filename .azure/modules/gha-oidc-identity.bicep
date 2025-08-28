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

@description('Grant AKS access to the identity using this built-in role; default is AKS RBAC Cluster Admin.')
param aksRoleDefinitionId string = '0ab0a1a7-8d01-4a35-8b0a-8ec5f50dfca1' // Azure Kubernetes Service RBAC Cluster Admin

@description('Whether to grant AKS RBAC role to the identity.')
param grantAksAccess bool = true

@description('Optionally, provide the AKS kubelet managed identity objectId to attach ACR pull to the cluster (emulates az aks update --attach-acr). Leave empty to skip.')
@secure()
param aksKubeletIdentityObjectId string = ''

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
    roleDefinitionId: aksRoleDefinitionId
  }
}

// ------------- Outputs -------------
output clientId string = uai.properties.clientId
output principalId string = uai.properties.principalId
output federatedSubject string = subject
