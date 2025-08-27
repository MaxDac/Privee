#!/bin/bash

# Exit on error
set -e

# Set variables
RESOURCE_GROUP="privee-dev-rg"
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

# Get Key Vault name and construct Cert URI
echo "Fetching Key Vault details..."
KEYVAULT_NAME=$(az keyvault list --resource-group "$RESOURCE_GROUP" --query "[0].name" -o tsv)
CERT_URI="https://""$KEYVAULT_NAME"".vault.azure.net/certificates/""$CERT_NAME"

# Create a temporary ingress file with placeholders replaced
PROCESSED_INGRESS_FILE="$(dirname "$0")/ingress-processed.yml"
cp "$(dirname "$0")/ingress.yml" "$PROCESSED_INGRESS_FILE"

# Replace placeholders
sed -i "s|\${YOUR_DOMAIN}|${DOMAIN}|g" "$PROCESSED_INGRESS_FILE"
sed -i "s|\${CERT_URI}|${CERT_URI}|g" "$PROCESSED_INGRESS_FILE"

echo "Applying manifests with real values..."

# Deploy Kubernetes manifests
echo "Deploying Kubernetes manifests..."
kubectl apply -f "$(dirname "$0")/secrets.yml"
kubectl apply -f "$(dirname "$0")/service.yml"
kubectl apply -f "$(dirname "$0")/headless-service.yml"
kubectl apply -f "$(dirname "$0")/deployment.yml"
kubectl apply -f "$PROCESSED_INGRESS_FILE"

# Clean up the processed file
rm "$PROCESSED_INGRESS_FILE"

echo "Kubernetes deployment completed successfully."
