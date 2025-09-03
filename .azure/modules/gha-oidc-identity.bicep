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

// Azure built-in role definition IDs - verified from Microsoft documentation
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

// ------------- Federated Identity Credential -------------
resource federatedCredential 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2023-01-31' = {
  parent: uai
  name: 'github-actions'
  properties: {
    issuer: issuer
    subject: subject
    audiences: [
      audience
    ]
  }
}

// ------------- ACR Build Custom Role Definition -------------
// Deterministic GUID for the custom role definition
var acrBuildUploadRoleGuid = guid(subscription().id, 'acr-build-upload-role', namePrefix)

// Minimal custom role containing only the actions needed for ACR build operations
// This role provides the minimum permissions required for GitHub Actions to execute 'az acr build' commands
resource acrBuildUploadRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' = {
  name: acrBuildUploadRoleGuid
  properties: {
    roleName: '${namePrefix} ACR Build - Upload and Schedule'
    description: 'Minimal custom role to allow ACR build operations: obtaining SAS URL for context upload and scheduling build runs.'
    type: 'CustomRole'
    permissions: [
      {
        actions: [
          // Required to obtain a SAS URL for uploading the build context (source code) to ACR's storage
          'Microsoft.ContainerRegistry/registries/listBuildSourceUploadUrl/action'
          // Required to schedule and execute the actual build operation in ACR
          'Microsoft.ContainerRegistry/registries/scheduleRun/action'
        ]
        notActions: []
      }
    ]
    assignableScopes: [
      resourceId(acrResourceGroup, 'Microsoft.ContainerRegistry/registries', acrName)
    ]
  }
}

// ------------- Modules for role assignments (cross-RG safe) -------------
// Note: module paths are relative to this file's directory

// Assign standard ACR roles (AcrPush for pushing images, optional AcrPull for kubelet)
// AcrPush: Allows pushing container images to the registry after they are built
// AcrPull: Allows AKS kubelet to pull images from the registry during pod creation
module assignAcr './acr-role-assignment.bicep' = {
  name: '${uai.name}-acr-assignments'
  scope: resourceGroup(acrResourceGroup)
  params: {
    acrName: acrName
    principalObjectId: uai.properties.principalId
    kubeletIdentityObjectId: aksKubeletIdentityObjectId
  }
}

// Assign the custom ACR Build role for GitHub Actions CI/CD operations
// This provides minimal permissions needed for 'az acr build' command execution:
// - listBuildSourceUploadUrl: Get SAS URL to upload source code to ACR's temporary storage
// - scheduleRun: Schedule and execute the container image build process in ACR
module assignAcrBuildRole './acr-build-role-assignment.bicep' = {
  name: '${uai.name}-acr-build-assignment'
  scope: resourceGroup(acrResourceGroup)
  params: {
    acrName: acrName
    principalObjectId: uai.properties.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrBuildUploadRoleGuid)
  }
  dependsOn: [
    acrBuildUploadRole
  ]
}

// Assign AKS RBAC Cluster Admin role for Kubernetes management operations
// This allows GitHub Actions to deploy applications, update configurations, and manage Kubernetes resources
// ClusterAdmin provides full administrative access to the AKS cluster via kubectl
module assignAks './aks-rbac-assignment.bicep' = if (grantAksAccess) {
  name: '${uai.name}-aks-rbac'
  scope: resourceGroup(aksResourceGroup)
  params: {
    aksName: aksName
    principalObjectId: uai.properties.principalId
    roleDefinitionId: aksRbacClusterAdminRoleId
    roleName: 'ClusterAdmin'
  }
}

// Assign AKS Cluster User role for obtaining kubeconfig credentials
// This allows GitHub Actions to run 'az aks get-credentials' to authenticate with the AKS cluster
// Required for any kubectl operations against the cluster
module assignAksGetCreds './aks-rbac-assignment.bicep' = if (grantAksAccess) {
  name: '${uai.name}-aks-getcreds'
  scope: resourceGroup(aksResourceGroup)
  params: {
    aksName: aksName
    principalObjectId: uai.properties.principalId
    roleDefinitionId: aksClusterUserRoleId
    roleName: 'ClusterUser'
  }
}

// ------------- Resource Group Reader Access -------------
// Grant Reader role at resource group scope to allow listing resources.
// Required by the GitHub action which pushes images to the ACR.
var readerRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'acdd72a7-3385-48ef-bd42-f606fba81ae7') // Reader role

resource resourceGroupReaderAccess 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, 'reader', uaiName)
  properties: {
    roleDefinitionId: readerRoleId
    principalId: uai.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// ------------- Outputs -------------
output clientId string = uai.properties.clientId
output principalId string = uai.properties.principalId
output federatedSubject string = subject
