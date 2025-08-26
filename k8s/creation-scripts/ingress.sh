#!/bin/bash

echo "🚀 Setting up Azure Application Routing add-on (managed NGINX) with Key Vault..."

export AKS_RG="Privee"
export AKS_NAME="Privee"
export PUBLIC_IP_NAME="privee-public-ip"
export KV_NAME="Privee-KV"

# Get the node resource group and public IP address
NODE_RESOURCE_GROUP=$(az aks show \
    --name "$AKS_NAME" \
    --resource-group "$AKS_RG" \
    --query nodeResourceGroup \
    --output tsv)

PUBLIC_IP_ADDRESS=$(az network public-ip show \
    --resource-group "$NODE_RESOURCE_GROUP" \
    --name "$PUBLIC_IP_NAME" \
    --query ipAddress \
    --output tsv)

echo "✅ Using static IP: $PUBLIC_IP_ADDRESS"
echo "✅ Node resource group: $NODE_RESOURCE_GROUP"
echo "✅ Key Vault: $KV_NAME"

# Enable Azure Application Routing add-on (managed NGINX)
echo "📦 Enabling Azure Application Routing add-on..."
az aks approuting enable -g "$AKS_RG" -n "$AKS_NAME"

if [ $? -eq 0 ]; then
    echo "✅ Application Routing add-on enabled!"
else
    echo "❌ Failed to enable Application Routing add-on"
    exit 1
fi

# Configure Application Routing to use the static IP
echo "🔧 Configuring Application Routing with static IP..."
az aks approuting zone add -g "$AKS_RG" -n "$AKS_NAME" \
    --ids="$PUBLIC_IP_ADDRESS" \
    --attach-zones

if [ $? -eq 0 ]; then
    echo "✅ Static IP configured with Application Routing!"
else
    echo "❌ Failed to configure static IP with Application Routing"
    exit 1
fi

# Enable Key Vault integration for SSL certificates
echo "🔐 Enabling Key Vault integration for SSL certificates..."
az aks approuting zone add -g "$AKS_RG" -n "$AKS_NAME" \
    --ids="/subscriptions/$(az account show --query id -o tsv)/resourcegroups/Privee-KV/providers/Microsoft.KeyVault/vaults/$KV_NAME" \
    --attach-zones

if [ $? -eq 0 ]; then
    echo "✅ Key Vault integration enabled!"
else
    echo "❌ Failed to enable Key Vault integration"
    exit 1
fi

echo ""
echo "✅ Azure Application Routing (managed NGINX) setup completed!"
echo ""
echo "📝 Configuration Summary:"
echo "- Application Routing: Enabled"
echo "- Static IP: $PUBLIC_IP_ADDRESS"
echo "- Key Vault: $KV_NAME"
echo "- SSL Certificate Management: Integrated with Key Vault"
echo ""
echo "🔧 Next steps:"
echo "1. Wait for the managed NGINX controller to be ready (may take a few minutes)"
echo "2. Check with: kubectl get pods -n app-routing-system"
echo "3. Apply your ingress configuration with webapprouting.kubernetes.azure.com class"
echo "4. Certificates will be automatically managed through Key Vault integration"