#!/bin/bash

# Exit on error
set -e

# Set variables
RESOURCE_GROUP="privee-dev-rg"
KV_RESOURCE_GROUP="privee-dev-kv-rg"
AKS_NAME="privee-aks"
# Option B with HTTPS enforced: use the Ingress public IP's DNS label as FQDN and terminate TLS with a cert from Key Vault.
# REQUIRED: set CERT_NAME to a certificate that exists in Key Vault and matches the final INGRESS_HOST; set DNS_LABEL (or let it auto-generate).
DNS_LABEL=""
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
  echo "Error: Could not resolve Key Vault ID."
  exit 1
fi

# Resolve tenant ID from the KV (preferred), then fallback to the current account
TENANT_ID=$(az account show --query tenantId -o tsv 2>/dev/null)

# Resolve kubelet identity clientId (used by CSI on nodes)
UAMI_CLIENT_ID=$(az aks show -g "$RESOURCE_GROUP" -n "$AKS_NAME" --query "identityProfile.kubeletidentity.clientId" -o tsv)
KUBELET_OBJID=$(az aks show -g "$RESOURCE_GROUP" -n "$AKS_NAME" --query "identityProfile.kubeletidentity.objectId" -o tsv)
if [ -z "$UAMI_CLIENT_ID" ] || [ -z "$KUBELET_OBJID" ]; then
  echo "Error: AKS kubelet identity not found. Ensure the cluster is managed identity enabled."
  exit 1
fi

# Ensure Key Vault Secrets User on the vault for the kubelet identity
HAS_ASSIGNMENT=$(az role assignment list --scope "$KV_ID" \
  --assignee-object-id "$KUBELET_OBJID" \
  --query "[?roleDefinitionName=='Key Vault Secrets User'] | length(@)" -o tsv 2>/dev/null || echo "0")

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

if [ -z "$CERT_NAME" ]; then
  echo "Error: CERT_NAME is required to enforce HTTPS with Key Vault. Set CERT_NAME to a certificate name in Key Vault."
  exit 1
fi
CERT_URI="https://$KEYVAULT_NAME.vault.azure.net/certificates/$CERT_NAME"

# Create a temporary ingress file with placeholders replaced
PROCESSED_INGRESS_FILE="$(dirname "$0")/ingress-processed.yml"
cp "$(dirname "$0")/ingress.yml" "$PROCESSED_INGRESS_FILE"

# Create a temporary SecretProviderClass file with placeholders replaced (only if Key Vault is configured)
PROCESSED_SPC_FILE=""
if [ -n "$KEYVAULT_NAME" ]; then
  PROCESSED_SPC_FILE="$(dirname "$0")/secret-provider-class-processed.yml"
  cp "$(dirname "$0")/secret-provider-class.yml" "$PROCESSED_SPC_FILE"
fi

#############################
# Discover Ingress Public IP and set DNS label
#############################
echo "Discovering Ingress public IP from app-routing-system..."
INGRESS_IP=$(kubectl get svc -n app-routing-system -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
if [ -z "$INGRESS_IP" ]; then
  # Fallback: try reading from the ingress status
  INGRESS_IP=$(kubectl get ingress privee-ingress -n default -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
fi
if [ -z "$INGRESS_IP" ]; then
  echo "Error: Could not determine Ingress public IP. Ensure the app routing add-on is enabled and the controller service has a public IP."
  exit 1
fi
echo "Ingress IP is: $INGRESS_IP"

NODE_RG=$(az aks show --resource-group "$RESOURCE_GROUP" --name "$AKS_NAME" --query nodeResourceGroup -o tsv)
PIP_NAME=$(az network public-ip list -g "$NODE_RG" --query "[?ipAddress=='$INGRESS_IP'].name" -o tsv)
if [ -z "$PIP_NAME" ]; then
  echo "Error: Could not find Public IP resource in node resource group $NODE_RG for IP $INGRESS_IP"
  echo "Available Public IPs:"
  az network public-ip list -g "$NODE_RG" -o table
  exit 1
fi

CURRENT_FQDN=$(az network public-ip show -g "$NODE_RG" -n "$PIP_NAME" --query "dnsSettings.fqdn" -o tsv)
if [ -z "$CURRENT_FQDN" ]; then
  if [ -z "$DNS_LABEL" ]; then
    # Generate a label: <aksname>-<random>
    RAND=$(head /dev/urandom | tr -dc a-z0-9 | head -c 5)
    DNS_LABEL=$(echo "$AKS_NAME-$RAND" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-')
  fi
  echo "Setting DNS label '$DNS_LABEL' on Public IP $PIP_NAME..."
  az network public-ip update -g "$NODE_RG" -n "$PIP_NAME" --dns-name "$DNS_LABEL" >/dev/null
  CURRENT_FQDN=$(az network public-ip show -g "$NODE_RG" -n "$PIP_NAME" --query "dnsSettings.fqdn" -o tsv)
fi

if [ -z "$CURRENT_FQDN" ]; then
  echo "Error: Failed to obtain FQDN for Public IP $PIP_NAME"
  exit 1
fi

INGRESS_HOST="$CURRENT_FQDN"
echo "Using INGRESS_HOST: $INGRESS_HOST"

# Replace placeholders in ingress
sed -i "s|\${INGRESS_HOST}|${INGRESS_HOST}|g" "$PROCESSED_INGRESS_FILE"
sed -i "s|\${CERT_URI}|${CERT_URI}|g" "$PROCESSED_INGRESS_FILE"

# Always keep TLS; ensure the Key Vault annotation and TLS block are present via placeholder substitution above.

if [ -n "$PROCESSED_SPC_FILE" ]; then
  # Replace placeholders in SecretProviderClass
  sed -i "s|\${KEYVAULT_NAME}|${KEYVAULT_NAME}|g" "$PROCESSED_SPC_FILE"
  sed -i "s|\${TENANT_ID}|${TENANT_ID}|g" "$PROCESSED_SPC_FILE"
  sed -i "s|\${UAMI_CLIENT_ID}|${UAMI_CLIENT_ID}|g" "$PROCESSED_SPC_FILE"
fi

# Prepare a processed deployment to inject INGRESS_HOST into PHX_HOST
PROCESSED_DEPLOY_FILE="$(dirname "$0")/deployment-processed.yml"
cp "$(dirname "$0")/deployment.yml" "$PROCESSED_DEPLOY_FILE"
sed -i "s|\${INGRESS_HOST}|${INGRESS_HOST}|g" "$PROCESSED_DEPLOY_FILE"

echo "Applying manifests with real values..."

# Deploy Kubernetes manifests in the correct order
echo "Deploying Kubernetes manifests..."

# Deploy SecretProviderClass and wait for it to be ready
if [ -n "$PROCESSED_SPC_FILE" ]; then
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
fi

# Deploy services
echo "Applying services..."
kubectl apply -f "$(dirname "$0")/service.yml"
kubectl apply -f "$(dirname "$0")/headless-service.yml"

# Deploy the application
echo "Applying deployment..."
kubectl apply -f "$PROCESSED_DEPLOY_FILE"

# Deploy ingress
echo "Applying ingress..."
kubectl apply -f "$PROCESSED_INGRESS_FILE"

# Clean up the processed files
rm "$PROCESSED_INGRESS_FILE"
[ -n "$PROCESSED_SPC_FILE" ] && rm "$PROCESSED_SPC_FILE"
rm "$PROCESSED_DEPLOY_FILE"

echo "Kubernetes deployment completed successfully."
if [ -n "$CERT_URI" ]; then
  echo "Your application should be available at: https://${INGRESS_HOST}"
else
  echo "Your application should be available at: http://${INGRESS_HOST}"
fi

# Wait for deployment to be ready
echo "Waiting for deployment to be ready..."
kubectl rollout status deployment/privee --timeout=300s

# Show pod status
echo "Pod status:"
kubectl get pods -l app=privee
