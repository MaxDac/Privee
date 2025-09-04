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

# Get the current authentication context
CURRENT_ACCOUNT_TYPE=$(az account show --query "user.type" -o tsv)
echo "🔍 Current account type: $CURRENT_ACCOUNT_TYPE"

# Get the appropriate object ID based on authentication type
if [ "$CURRENT_ACCOUNT_TYPE" = "servicePrincipal" ]; then
    # For service principal (OIDC/CI), get the service principal object ID
    CLIENT_ID=$(az account show --query "user.name" -o tsv)
    # The user.name field contains the client ID for service principals, we need to get the object ID
    ASSIGNEE_OBJECT_ID=$(az ad sp show --id "$CLIENT_ID" --query "id" -o tsv)
    echo "🤖 Service principal object ID: $ASSIGNEE_OBJECT_ID"
else
    # For user authentication, get the signed-in user object ID
    ASSIGNEE_OBJECT_ID=$(az ad signed-in-user show --query id -o tsv)
    echo "👤 Current user object ID: $ASSIGNEE_OBJECT_ID"
fi

echo "🔑 Granting Key Vault Secrets Officer role to current principal..."
az role assignment create \
    --role "Key Vault Secrets Officer" \
    --assignee "$ASSIGNEE_OBJECT_ID" \
    --scope "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/privee-dev-kv-rg/providers/Microsoft.KeyVault/vaults/$VAULT_NAME" \
    --output none || echo "⚠️  Role assignment may already exist"

# Wait a moment for role assignment propagation
echo "⏳ Waiting for role assignment propagation..."
sleep 10

echo "🌩️ Creating COSMOS_USER in Key Vault..."
az keyvault secret set \
    --vault-name "$VAULT_NAME" \
    --name "COSMOS-USER" \
    --value "citus" \
    --output none

echo "🔓 Creating COSMOS_DB in Key Vault..."
az keyvault secret set \
    --vault-name "$VAULT_NAME" \
    --name "COSMOS-DB" \
    --value "citus" \
    --output none

echo "🔒 Creating COSMOS_PASSWORD in Key Vault..."
# Using the same password as before for consistency
COSMOS_PASSWORD="~KEEN4e~"
az keyvault secret set \
    --vault-name "$VAULT_NAME" \
    --name "COSMOS-PASSWORD" \
    --value "$COSMOS_PASSWORD" \
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
echo "  - COSMOS-USER: citus"
echo "  - COSMOS-DB: citus"
echo "  - COSMOS-PASSWORD: ~KEEN4e~"
echo "  - privee-secret-key-base: QExJc2NvZW55c2RkZzIzeDFjTTk9d01OdDZWYXRscXp3N1VlT2p5VmNRTk0wZ2d4eDQx"