#!/bin/bash

# Azure AKS Static IP Setup Script
# This script creates a static public IP for the Privee LoadBalancer service

set -e

echo "🌐 Setting up Azure static IP for AKS LoadBalancer..."

# Configuration variables - UPDATE THESE FOR YOUR ENVIRONMENT
AKS_CLUSTER_NAME="Privee"           # Your AKS cluster name
AKS_RESOURCE_GROUP="Privee"         # Your main resource group
LOCATION="westeurope"               # Your Azure region
PUBLIC_IP_NAME="privee-public-ip"   # Name for the public IP resource

# Check if Azure CLI is available
if ! command -v az &> /dev/null; then
    echo "❌ Azure CLI is not installed or not in PATH"
    echo "Please install Azure CLI: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    exit 1
fi

# Check if user is logged into Azure
if ! az account show &> /dev/null; then
    echo "❌ Not logged into Azure"
    echo "Please run 'az login' first"
    exit 1
fi

# Get the node resource group (managed by AKS)
echo "📋 Getting AKS node resource group..."
NODE_RESOURCE_GROUP=$(az aks show \
    --name "$AKS_CLUSTER_NAME" \
    --resource-group "$AKS_RESOURCE_GROUP" \
    --query nodeResourceGroup \
    --output tsv)

if [ -z "$NODE_RESOURCE_GROUP" ]; then
    echo "❌ Could not find AKS cluster or node resource group"
    echo "Please check your cluster name: $AKS_CLUSTER_NAME"
    echo "Please check your resource group: $AKS_RESOURCE_GROUP"
    exit 1
fi

echo "✅ Found node resource group: $NODE_RESOURCE_GROUP"

# Create static public IP
echo "🔧 Creating static public IP..."
az network public-ip create \
    --resource-group "$NODE_RESOURCE_GROUP" \
    --name "$PUBLIC_IP_NAME" \
    --sku Standard \
    --allocation-method static \
    --location "$LOCATION" \
    --output table

# Get the IP address
PUBLIC_IP_ADDRESS=$(az network public-ip show \
    --resource-group "$NODE_RESOURCE_GROUP" \
    --name "$PUBLIC_IP_NAME" \
    --query ipAddress \
    --output tsv)

echo "✅ Static public IP created: $PUBLIC_IP_ADDRESS"

# Get cluster identity for permissions
echo "🔐 Setting up permissions for AKS cluster identity..."

# Check if cluster uses system-assigned or user-assigned managed identity
IDENTITY_TYPE=$(az aks show \
    --name "$AKS_CLUSTER_NAME" \
    --resource-group "$AKS_RESOURCE_GROUP" \
    --query identity.type \
    --output tsv)

if [ "$IDENTITY_TYPE" = "SystemAssigned" ]; then
    echo "📋 Using system-assigned managed identity"
    CLIENT_ID=$(az aks show \
        --name "$AKS_CLUSTER_NAME" \
        --resource-group "$AKS_RESOURCE_GROUP" \
        --query identity.principalId \
        --output tsv)
elif [ "$IDENTITY_TYPE" = "UserAssigned" ]; then
    echo "📋 Using user-assigned managed identity"
    CLIENT_ID=$(az aks show \
        --name "$AKS_CLUSTER_NAME" \
        --resource-group "$AKS_RESOURCE_GROUP" \
        --query identity.userAssignedIdentities.*.clientId \
        --output tsv)
else
    echo "⚠️  Cluster is using service principal (deprecated)"
    echo "Consider upgrading to managed identity"
    exit 1
fi

# Get resource group scope
RG_SCOPE=$(az group show \
    --name "$NODE_RESOURCE_GROUP" \
    --query id \
    --output tsv)

# Assign Network Contributor role to the managed identity
echo "🔐 Assigning Network Contributor role..."
az role assignment create \
    --assignee "$CLIENT_ID" \
    --role "Network Contributor" \
    --scope "$RG_SCOPE" \
    --output none

echo ""
echo "🎉 Setup completed successfully!"
echo ""
echo "📝 Configuration Summary:"
echo "  - Public IP Name: $PUBLIC_IP_NAME"
echo "  - Public IP Address: $PUBLIC_IP_ADDRESS"
echo "  - Node Resource Group: $NODE_RESOURCE_GROUP"
echo "  - Location: $LOCATION"
echo ""
echo "🔧 Next Steps:"
echo "  1. Update your services.yml with the new IP address:"
echo "     loadBalancerIP: $PUBLIC_IP_ADDRESS"
echo ""
echo "  2. Or use the recommended annotation approach:"
echo "     service.beta.kubernetes.io/azure-pip-name: $PUBLIC_IP_NAME"
echo "     service.beta.kubernetes.io/azure-load-balancer-resource-group: $NODE_RESOURCE_GROUP"
echo ""
echo "  3. Deploy your services:"
echo "     kubectl apply -f k8s/services.yml"
echo ""
echo "✨ Your LoadBalancer will be accessible at: http://$PUBLIC_IP_ADDRESS"
