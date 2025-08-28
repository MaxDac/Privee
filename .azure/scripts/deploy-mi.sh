#!/bin/bash
set -euo pipefail

# -----------------------------------------------------------------------------
# This script deploys the GitHub Actions OIDC identity and its associated
# role assignments for ACR and AKS.
#
# It resolves role definition IDs dynamically and uses sensible defaults.
# -----------------------------------------------------------------------------

# --- Configuration ---
# The resource group where the User-Assigned Managed Identity will be created.
IDENTITY_RESOURCE_GROUP="privee-dev-rg"

# The Azure location for the identity. If left empty, it will use the resource group's location.
LOCATION="northeurope"

# A prefix for the managed identity name.
NAME_PREFIX="privee"

# Your GitHub organization or username.
GITHUB_OWNER="MaxDac"

# Your GitHub repository name.
GITHUB_REPO="Privee"

# The resource group where your Azure Container Registry (ACR) is located.
ACR_RESOURCE_GROUP="privee-dev-rg"

# The name of your Azure Container Registry (ACR).
# Default is computed from NAME_PREFIX, e.g., "priveeregistry".
ACR_NAME="${NAME_PREFIX}registry"

# The resource group where your Azure Kubernetes Service (AKS) cluster is located.
AKS_RESOURCE_GROUP="privee-dev-rg"

# The name of your Azure Kubernetes Service (AKS) cluster.
AKS_NAME="privee-aks"

# (Optional) The object ID of the AKS kubelet managed identity.
# This is needed to grant AcrPull permissions to the cluster.
# If left empty, the script will try to detect it automatically.
AKS_KUBELET_IDENTITY_OBJECT_ID=""

# --- Role Names for dynamic lookup ---
AKS_ROLE_NAME="Azure Kubernetes Service RBAC Cluster Admin"
AKS_GETCREDS_ROLE_NAME="Azure Kubernetes Service Cluster User Role"


# --- Pre-flight checks and setup ---
echo "Checking Azure login status..."
if ! az account show > /dev/null 2>&1; then
  echo "ERROR: You are not logged in to Azure. Please run 'az login' to authenticate."
  exit 1
fi

echo "Validating and resolving necessary resources..."

# Auto-populate kubelet identity if not provided
if [[ -z "$AKS_KUBELET_IDENTITY_OBJECT_ID" ]]; then
    echo "Attempting to detect AKS kubelet identity for '$AKS_NAME' in RG '$AKS_RESOURCE_GROUP'..."
    AKS_KUBELET_IDENTITY_OBJECT_ID="$(az aks show -n "$AKS_NAME" -g "$AKS_RESOURCE_GROUP" --query "identityProfile.kubeletidentity.objectId" -o tsv 2>/dev/null || true)"
    if [[ -n "$AKS_KUBELET_IDENTITY_OBJECT_ID" ]]; then
      echo "Detected AKS kubelet identity objectId: $AKS_KUBELET_IDENTITY_OBJECT_ID"
    else
      echo "Warning: Could not detect kubelet identity objectId. If you need to pull from ACR, the role assignment might need to be created manually."
    fi
fi

# Resolve Role Definition IDs
echo "Resolving role definition IDs..."
AKS_ROLE_ID=$(az role definition list --name "$AKS_ROLE_NAME" --query "[0].id" -o tsv)
if [[ -z "$AKS_ROLE_ID" ]]; then
    echo "ERROR: Could not resolve role definition ID for '$AKS_ROLE_NAME'." >&2
    exit 1
fi
echo "Resolved '$AKS_ROLE_NAME' -> $AKS_ROLE_ID"

AKS_GETCREDS_ROLE_ID=$(az role definition list --name "$AKS_GETCREDS_ROLE_NAME" --query "[0].id" -o tsv)
if [[ -z "$AKS_GETCREDS_ROLE_ID" ]]; then
    echo "ERROR: Could not resolve role definition ID for '$AKS_GETCREDS_ROLE_NAME'." >&2
    exit 1
fi
echo "Resolved '$AKS_GETCREDS_ROLE_NAME' -> $AKS_GETCREDS_ROLE_ID"


# --- Deployment ---
echo "Starting Bicep deployment for GitHub OIDC Identity..."

# Build parameter list
PARAMS=(
    namePrefix="$NAME_PREFIX"
    location="$LOCATION"
    githubOwner="$GITHUB_OWNER"
    githubRepo="$GITHUB_REPO"
    acrResourceGroup="$ACR_RESOURCE_GROUP"
    acrName="$ACR_NAME"
    aksResourceGroup="$AKS_RESOURCE_GROUP"
    aksName="$AKS_NAME"
    aksKubeletIdentityObjectId="$AKS_KUBELET_IDENTITY_OBJECT_ID"
    aksRoleDefinitionId="$(basename "$AKS_ROLE_ID")"
    aksGetCredentialsRoleDefinitionId="$(basename "$AKS_GETCREDS_ROLE_ID")"
)

az deployment group create \
  --name "gha-oidc-deployment" \
  --resource-group "$IDENTITY_RESOURCE_GROUP" \
  --template-file "../modules/gha-oidc-identity.bicep" \
  --parameters "${PARAMS[@]}"

echo "Deployment finished."