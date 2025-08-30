#!/bin/bash

# Deploy standalone Key Vault template
# This script should be run before deploying the main infrastructure

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "Error: jq is not installed. Please install jq to run this script."
    echo "On Ubuntu/Debian: sudo apt-get install jq"
    echo "On macOS: brew install jq"
    exit 1
fi

# Default values
LOCATION="northeurope"
SUBSCRIPTION_ID=""
DEPLOYMENT_NAME="keyvault-deployment-$(date +%s)"
AUTO_RECOVER=false

# Helper: ensure resource group exists in a location
ensure_rg_exists() {
  local rg_name="$1"
  local rg_location="$2"

  if ! az group show --name "$rg_name" >/dev/null 2>&1; then
    echo "Resource group '$rg_name' not found. Creating in location: $rg_location"
    az group create --name "$rg_name" --location "$rg_location" >/dev/null
    echo "Resource group '$rg_name' created."
  else
    echo "Resource group '$rg_name' already exists."
  fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --location|-l)
      LOCATION="$2"
      shift 2
      ;;
    --subscription|-s)
      SUBSCRIPTION_ID="$2"
      shift 2
      ;;
    --deployment-name|-n)
      DEPLOYMENT_NAME="$2"
      shift 2
      ;;
    --auto-recover)
      AUTO_RECOVER=true
      shift
      ;;
    --help|-h)
      echo "Usage: $0 [options]"
      echo "Options:"
      echo "  --location, -l         Azure region (default: northeurope)"
      echo "  --subscription, -s     Azure subscription ID"
      echo "  --deployment-name, -n  Deployment name (default: keyvault-deployment-{timestamp})"
      echo "  --auto-recover         Automatically recover soft-deleted Key Vault if found"
      echo "  --help, -h             Show this help message"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Set subscription if provided
if [[ -n "$SUBSCRIPTION_ID" ]]; then
  echo "Setting Azure subscription to: $SUBSCRIPTION_ID"
  az account set --subscription "$SUBSCRIPTION_ID"
fi

# Verify current subscription
CURRENT_SUBSCRIPTION=$(az account show --query id -o tsv)
echo "Deploying to subscription: $CURRENT_SUBSCRIPTION"

# Check for existing soft-deleted Key Vault
echo "Checking for existing soft-deleted Key Vault..."
DELETED_KV=$(az keyvault list-deleted --query "[?name=='privee-kv']" -o json)

if [ "$DELETED_KV" != "[]" ] && [ -n "$DELETED_KV" ]; then
  echo "Found soft-deleted Key Vault 'privee-kv'"
  
  if [ "$AUTO_RECOVER" = true ]; then
    echo "Auto-recovering soft-deleted Key Vault..."
    KV_LOCATION=$(echo "$DELETED_KV" | jq -r '.[0].properties.location')
  # Determine expected resource group name from parameters file
  NAME_PREFIX=$(jq -r '.parameters.namePrefix.value' "$SCRIPT_DIR/keyvault-standalone.parameters.json")
  ENVIRONMENT=$(jq -r '.parameters.environment.value' "$SCRIPT_DIR/keyvault-standalone.parameters.json")
  KEYVAULT_RG_NAME="${NAME_PREFIX}-${ENVIRONMENT}-kv-rg"
  # Ensure resource group exists prior to recovery (required by Azure)
  ensure_rg_exists "$KEYVAULT_RG_NAME" "$KV_LOCATION"
    az keyvault recover --name "privee-kv" --location "$KV_LOCATION"
    echo "Key Vault recovered successfully. Skipping deployment."
    
    # Output the recovered Key Vault information
    echo ""
    echo "==================== RECOVERY OUTPUTS ===================="
    RECOVERED_KV_ID=$(az keyvault show --name "privee-kv" --query id -o tsv)
  RECOVERED_KV_RG=$(az keyvault show --name "privee-kv" --query resourceGroup -o tsv)
    echo "Key Vault ID: $RECOVERED_KV_ID"
    echo "Key Vault Name: privee-kv"
    echo "Key Vault Resource Group: $RECOVERED_KV_RG"
    echo "=============================================================="
    echo ""
    echo "To use this Key Vault in the main deployment, update the 'keyVaultId' parameter in main.parameters.json:"
    echo "  \"keyVaultId\": {"
    echo "    \"value\": \"$RECOVERED_KV_ID\""
    echo "  }"
    exit 0
  else
    echo "A soft-deleted Key Vault 'privee-kv' already exists."
    echo "Options:"
    echo "1. Recover the existing Key Vault (recommended - keeps existing secrets)"
    echo "2. Cancel and run with --auto-recover flag for automatic recovery"
    echo "3. Use the existing purge script: ./scripts/purge-kv.sh"
    
    read -p "Please choose an option (1/2/3): " -n 1 -r
    echo
    
    case $REPLY in
      1)
        echo "Recovering soft-deleted Key Vault..."
        KV_LOCATION=$(echo "$DELETED_KV" | jq -r '.[0].properties.location')
  # Determine expected resource group name from parameters file
  NAME_PREFIX=$(jq -r '.parameters.namePrefix.value' "$SCRIPT_DIR/keyvault-standalone.parameters.json")
  ENVIRONMENT=$(jq -r '.parameters.environment.value' "$SCRIPT_DIR/keyvault-standalone.parameters.json")
  KEYVAULT_RG_NAME="${NAME_PREFIX}-${ENVIRONMENT}-kv-rg"
  # Ensure resource group exists prior to recovery (required by Azure)
  ensure_rg_exists "$KEYVAULT_RG_NAME" "$KV_LOCATION"
        az keyvault recover --name "privee-kv" --location "$KV_LOCATION"
        echo "Key Vault recovered successfully. Skipping deployment."
        
        # Output the recovered Key Vault information
        echo ""
        echo "==================== RECOVERY OUTPUTS ===================="
        RECOVERED_KV_ID=$(az keyvault show --name "privee-kv" --query id -o tsv)
        RECOVERED_KV_RG=$(az keyvault show --name "privee-kv" --query resourceGroup -o tsv)
        echo "Key Vault ID: $RECOVERED_KV_ID"
        echo "Key Vault Name: privee-kv"
        echo "Key Vault Resource Group: $RECOVERED_KV_RG"
        echo "=============================================================="
        echo ""
        echo "To use this Key Vault in the main deployment, update the 'keyVaultId' parameter in main.parameters.json:"
        echo "  \"keyVaultId\": {"
        echo "    \"value\": \"$RECOVERED_KV_ID\""
        echo "  }"
        exit 0
        ;;
      2)
        echo "Deployment cancelled. Run the script again with --auto-recover flag."
        exit 0
        ;;
      3)
        echo "Please run ./scripts/purge-kv.sh first, then run this script again."
        exit 0
        ;;
      *)
        echo "Invalid option. Deployment cancelled."
        exit 1
        ;;
    esac
  fi
fi

# Deploy the Key Vault template
echo "Deploying Key Vault to location: $LOCATION"
echo "Deployment name: $DEPLOYMENT_NAME"

az deployment sub create \
  --location "$LOCATION" \
  --template-file "$SCRIPT_DIR/modules/keyvault-standalone.bicep" \
  --parameters "$SCRIPT_DIR/keyvault-standalone.parameters.json" \
  --name "$DEPLOYMENT_NAME" \
  --verbose

# Get deployment outputs
echo ""
echo "Deployment completed. Getting outputs..."

KEY_VAULT_ID=$(az deployment sub show --name "$DEPLOYMENT_NAME" --query properties.outputs.keyVaultId.value -o tsv)
KEY_VAULT_NAME=$(az deployment sub show --name "$DEPLOYMENT_NAME" --query properties.outputs.keyVaultName.value -o tsv)
KEY_VAULT_RG=$(az deployment sub show --name "$DEPLOYMENT_NAME" --query properties.outputs.keyVaultResourceGroupName.value -o tsv)

echo ""
echo "==================== DEPLOYMENT OUTPUTS ===================="
echo "Key Vault ID: $KEY_VAULT_ID"
echo "Key Vault Name: $KEY_VAULT_NAME"
echo "Key Vault Resource Group: $KEY_VAULT_RG"
echo "=============================================================="
echo ""
echo "To use this Key Vault in the main deployment, update the 'keyVaultId' parameter in main.parameters.json:"
echo "  \"keyVaultId\": {"
echo "    \"value\": \"$KEY_VAULT_ID\""
echo "  }"
