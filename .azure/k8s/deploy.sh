#!/bin/bash

# Exit on error
set -e

# Set variables
RESOURCE_GROUP="privee-dev-rg"
KV_RESOURCE_GROUP="privee-dev-kv-rg"
AKS_NAME="privee-aks"
# Replace with your domain and cert name
DOMAIN="privee.northeurope.cloudapp.azure.com"
CERT_NAME="privee-tls"

# Check if logged in to Azure
if ! az account show > /dev/null 2>&1; then
    echo "You are not logged in to Azure. Please run 'az login' to authenticate."
    exit 1
fi

# Get AKS credentials
echo "Getting AKS credentials..."
az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$AKS_NAME" --overwrite-existing

# Check if Secrets Store CSI Driver is enabled
echo "Checking for Secrets Store CSI Driver..."
CSI_DRIVER_ENABLED=$(az aks show --resource-group "$RESOURCE_GROUP" --name "$AKS_NAME" --query "addonProfiles.azureKeyvaultSecretsProvider.enabled" -o tsv 2>/dev/null || echo "false")

if [ "$CSI_DRIVER_ENABLED" != "true" ]; then
    echo "Enabling Azure Key Vault Provider for Secrets Store CSI Driver..."
    az aks enable-addons --resource-group "$RESOURCE_GROUP" --name "$AKS_NAME" --addons azure-keyvault-secrets-provider
    echo "Waiting for add-on to be ready..."
    sleep 60
    
    # Verify the CSI driver pods are running
    echo "Waiting for CSI driver pods to be ready..."
    kubectl wait --for=condition=ready pod -l app=secrets-store-csi-driver -n kube-system --timeout=300s
    kubectl wait --for=condition=ready pod -l app=secrets-store-provider-azure -n kube-system --timeout=300s
else
    echo "Secrets Store CSI Driver is already enabled."
    # Still check if pods are ready
    echo "Verifying CSI driver pods are ready..."
    kubectl wait --for=condition=ready pod -l app=secrets-store-csi-driver -n kube-system --timeout=60s || echo "Warning: CSI driver pods may not be ready"
    kubectl wait --for=condition=ready pod -l app=secrets-store-provider-azure -n kube-system --timeout=60s || echo "Warning: Azure provider pods may not be ready"
fi

# Get Key Vault name and construct Cert URI
echo "Fetching Key Vault details..."
KEYVAULT_NAME=$(az keyvault list --resource-group "$KV_RESOURCE_GROUP" --query "[0].name" -o tsv)
if [ -z "$KEYVAULT_NAME" ]; then
  echo "Error: No Key Vault found in resource group '$KV_RESOURCE_GROUP'."
  exit 1
fi

# Get Key Vault scope
KV_ID=$(az keyvault show -g "$KV_RESOURCE_GROUP" -n "$KEYVAULT_NAME" --query id -o tsv)
if [ -z "$KV_ID" ]; then
  echo "Error: No Key Vault found in resource group '$KV_RESOURCE_GROUP'."
  exit 1
fi

# Resolve tenant ID from the KV (preferred), then fallback to the current account
TENANT_ID=$(az keyvault show --resource-group "$KV_RESOURCE_GROUP" --name "$KEYVAULT_NAME" --query "properties.tenantId" -o tsv 2>/dev/null)
[ -z "$TENANT_ID" ] && TENANT_ID=$(az account show --query tenantId -o tsv 2>/dev/null)
if [ -z "$TENANT_ID" ]; then
  echo "Error: Could not determine tenantId for Key Vault '$KEYVAULT_NAME'."
  exit 1
fi

# Resolve kubelet identity clientId (used by CSI on nodes)
UAMI_CLIENT_ID=$(az aks show -g "$RESOURCE_GROUP" -n "$AKS_NAME" --query "identityProfile.kubeletidentity.clientId" -o tsv 2>/dev/null)
if [ -z "$UAMI_CLIENT_ID" ]; then
  echo "Error: Could not determine AKS kubelet identity clientId. Ensure the cluster has a kubelet identity."
  exit 1
fi

KUBELET_OBJID=$(az aks show -g "$RESOURCE_GROUP" -n "$AKS_NAME" --query "identityProfile.kubeletidentity.objectId" -o tsv 2>/dev/null)
if [ -z "$KUBELET_OBJID" ]; then
  echo "Error: Could not determine AKS kubelet identity objectId. Ensure the cluster has a kubelet identity."
  exit 1
fi

# Ensure Key Vault Secrets User on the vault for the kubelet identity
HAS_ASSIGNMENT=$(az role assignment list --scope "$KV_ID" \
  --assignee-object-id "$KUBELET_OBJID" \
  --query "[?roleDefinitionName=='Key Vault Secrets User'] | length(@)" -o tsv)

if [ "$HAS_ASSIGNMENT" = "0" ] || [ -z "$HAS_ASSIGNMENT" ]; then
  echo "Granting 'Key Vault Secrets User' to kubelet identity on $KEYVAULT_NAME..."
  az role assignment create \
    --assignee-object-id "$KUBELET_OBJID" \
    --assignee-principal-type ServicePrincipal \
    --role "Key Vault Secrets User" \
    --scope "$KV_ID"
else
  echo "Kubelet identity already has 'Key Vault Secrets User' on $KEYVAULT_NAME."
fi

CERT_URI="https://""$KEYVAULT_NAME"".vault.azure.net/certificates/""$CERT_NAME"

# Create a temporary ingress file with placeholders replaced
PROCESSED_INGRESS_FILE="$(dirname "$0")/ingress-processed.yml"
cp "$(dirname "$0")/ingress.yml" "$PROCESSED_INGRESS_FILE"

# Create a temporary SecretProviderClass file with placeholders replaced
PROCESSED_SPC_FILE="$(dirname "$0")/secret-provider-class-processed.yml"
cp "$(dirname "$0")/secret-provider-class.yml" "$PROCESSED_SPC_FILE"

# Replace placeholders in ingress
sed -i "s|\${YOUR_DOMAIN}|app.${DOMAIN}|g" "$PROCESSED_INGRESS_FILE"
sed -i "s|\${CERT_URI}|${CERT_URI}|g" "$PROCESSED_INGRESS_FILE"

# Replace placeholders in SecretProviderClass
sed -i "s|\${KEYVAULT_NAME}|${KEYVAULT_NAME}|g" "$PROCESSED_SPC_FILE"
sed -i "s|\${TENANT_ID}|${TENANT_ID}|g" "$PROCESSED_SPC_FILE"
sed -i "s|\${UAMI_CLIENT_ID}|${UAMI_CLIENT_ID}|g" "$PROCESSED_SPC_FILE"

echo "Applying manifests with real values..."

# Deploy Kubernetes manifests in the correct order
echo "Deploying Kubernetes manifests..."

# Deploy SecretProviderClass and wait for it to be ready
echo "Applying SecretProviderClass..."
kubectl apply -f "$PROCESSED_SPC_FILE"

# Verify the SecretProviderClass was created
echo "Waiting for SecretProviderClass to be available..."
kubectl wait --for=condition=Established crd/secretproviderclasses.secrets-store.csi.x-k8s.io --timeout=60s || echo "Warning: CRD may not be ready"
sleep 10

# Verify SecretProviderClass exists
if ! kubectl get secretproviderclass azure-kv-privee -n default > /dev/null 2>&1; then
    echo "Error: SecretProviderClass 'azure-kv-privee' was not created successfully"
    echo "Available SecretProviderClasses:"
    kubectl get secretproviderclass -n default
    exit 1
fi
echo "SecretProviderClass 'azure-kv-privee' is ready"

# Deploy services
echo "Applying services..."
kubectl apply -f "$(dirname "$0")/service.yml"
kubectl apply -f "$(dirname "$0")/headless-service.yml"

# Deploy the application
echo "Applying deployment..."
kubectl apply -f "$(dirname "$0")/deployment.yml"

# Deploy ingress
echo "Applying ingress..."
kubectl apply -f "$PROCESSED_INGRESS_FILE"

# Clean up the processed files
rm "$PROCESSED_INGRESS_FILE"
rm "$PROCESSED_SPC_FILE"

echo "Kubernetes deployment completed successfully."
echo "Your application should be available at: https://app.${DOMAIN}"

# Wait for deployment to be ready
echo "Waiting for deployment to be ready..."
kubectl rollout status deployment/privee --timeout=300s

# Show pod status
echo "Pod status:"
kubectl get pods -l app=privee
