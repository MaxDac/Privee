// Module for creating User Managed Identity with OIDC federation
// This module is deployed at resource group scope

@description('Name for the User Managed Identity')
param identityName string

@description('Location for the identity resource')
param location string

@description('GitHub repository owner')
param githubOwner string

@description('GitHub repository name')
param githubRepo string

@description('OIDC subject for GitHub Actions authentication')
param oidcSubject string

@description('Environment name for tagging')
param environment string

// OIDC configuration
var issuer = 'https://token.actions.githubusercontent.com'
var subject = 'repo:${githubOwner}/${githubRepo}:${oidcSubject}'
var audience = 'api://AzureADTokenExchange'
var federatedCredentialName = 'github-actions-admin'

// ------------- User Managed Identity -------------
resource adminIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: identityName
  location: location
  tags: {
    Purpose: 'GitHub Actions Administrative Identity'
    Environment: environment
    Repository: '${githubOwner}/${githubRepo}'
    Subject: oidcSubject
  }
}

// ------------- Federated Identity Credential for OIDC -------------
resource federatedCredential 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2023-01-31' = {
  parent: adminIdentity
  name: federatedCredentialName
  properties: {
    issuer: issuer
    subject: subject
    audiences: [
      audience
    ]
  }
}

// ------------- Outputs -------------
output clientId string = adminIdentity.properties.clientId
output principalId string = adminIdentity.properties.principalId
output identityResourceId string = adminIdentity.id
output federatedSubject string = subject
