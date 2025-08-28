#!/bin/bash

# Migrate secrets to Azure Key Vault
# This script creates the secrets directly in Key Vault

set -e

# Configuration
VAULT_NAME="privee-kv"

echo "🔐 Creating secrets in Azure Key Vault: $VAULT_NAME"

# Check if user is logged in to Azure CLI
if ! az account show &> /dev/null; then
    echo "❌ Not logged in to Azure CLI. Please run 'az login' first."
    exit 1
fi

# Get current user object ID and grant Key Vault access
USER_OBJECT_ID=$(az ad signed-in-user show --query id -o tsv)
echo "👤 Current user object ID: $USER_OBJECT_ID"

echo "🔑 Granting Key Vault Secrets Officer role to current user..."
az role assignment create \
    --role "Key Vault Secrets Officer" \
    --assignee "$USER_OBJECT_ID" \
    --scope "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/privee-dev-kv-rg/providers/Microsoft.KeyVault/vaults/$VAULT_NAME" \
    --output none || echo "⚠️  Role assignment may already exist"

# Wait a moment for role assignment propagation
echo "⏳ Waiting for role assignment propagation..."
sleep 10

echo "� Creating POSTGRES_USER in Key Vault..."
az keyvault secret set \
    --vault-name "$VAULT_NAME" \
    --name "POSTGRES-USER" \
    --value "priveedbadmin" \
    --output none

echo "🔓 Creating POSTGRES_DB in Key Vault..."
az keyvault secret set \
    --vault-name "$VAULT_NAME" \
    --name "POSTGRES-DB" \
    --value "privee" \
    --output none

echo "🔒 Creating POSTGRES_PASSWORD in Key Vault..."
# Using the original value from secrets.yml (base64 decoded: ~KEEN4e~)
POSTGRES_PASSWORD="~KEEN4e~"
az keyvault secret set \
    --vault-name "$VAULT_NAME" \
    --name "POSTGRES-PASSWORD" \
    --value "$POSTGRES_PASSWORD" \
    --output none

echo "🔑 Creating Phoenix secret key base in Key Vault..."
# Using the original value from secrets.yml (base64 decoded)
SECRET_KEY_BASE="QExJc2NvZW55c2RkZzIzeDFjTTk9d01OdDZWYXRscXp3N1VlT2p5VmNRTk0wZ2d4eDQx"
az keyvault secret set \
    --vault-name "$VAULT_NAME" \
    --name "privee-secret-key-base" \
    --value "$SECRET_KEY_BASE" \
    --output none

echo "✅ All secrets have been created in Azure Key Vault!"

echo "✨ Creation complete!"
echo ""
echo "📝 Secrets created in Key Vault:"
echo "  - POSTGRES-USER: priveedbadmin"
echo "  - POSTGRES-DB: privee"
echo "  - POSTGRES-PASSWORD: ~^KAT4e~"
echo "  - privee-secret-key-base: QExJc2NvZW55c2RkZzIzeDFjTTk9d01OdDZWYXRscXp3N1VlT2p5VmNRTk0wZ2d4eDQx"