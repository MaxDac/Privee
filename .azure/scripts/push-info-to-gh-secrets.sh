#!/bin/bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Extract Managed Identity information and push to GitHub secrets
# This script retrieves subscription ID, client ID, and tenant ID from the
# deployed managed identity and sets them as GitHub repository secrets.
# -----------------------------------------------------------------------------

# --- Parse command line arguments ---
CI_MODE=false
while [[ $# -gt 0 ]]; do
  case $1 in
    --ci)
      CI_MODE=true
      shift
      ;;
    -h|--help)
      echo "Usage: $0 [--ci]"
      echo "  --ci    Skip GitHub CLI authentication check (for CI/CD environments)"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Use --help for usage information"
      exit 1
      ;;
  esac
done

# --- Configuration (update these to match your setup) ---
GITHUB_OWNER="MaxDac"
GITHUB_REPO="Privee"
RESOURCE_GROUP="privee-dev-rg"
MANAGED_IDENTITY_NAME="privee-gha-oidc"

# --- Prerequisites check ---
echo "Checking prerequisites..."

# Check if logged in to Azure
if ! az account show > /dev/null 2>&1; then
  echo "ERROR: You are not logged in to Azure. Please run 'az login' to authenticate."
  exit 1
fi

# Check if GitHub CLI is installed and authenticated
if ! command -v gh &> /dev/null; then
  echo "ERROR: GitHub CLI (gh) is not installed. Please install it first."
  echo "Installation instructions: https://cli.github.com/"
  exit 1
fi

if ! $CI_MODE; then
  if ! gh auth status > /dev/null 2>&1; then
    echo "ERROR: You are not authenticated with GitHub CLI. Please run 'gh auth login'."
    exit 1
  fi
else
  echo "✓ Running in CI mode - skipping GitHub CLI authentication check"
fi

echo "✓ Prerequisites met"

# --- Extract Azure information ---
echo "Extracting Azure information..."

# Get subscription ID
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
if [[ -z "$SUBSCRIPTION_ID" ]]; then
  echo "ERROR: Could not retrieve subscription ID"
  exit 1
fi
echo "✓ Subscription ID: $SUBSCRIPTION_ID"

# Get tenant ID
TENANT_ID=$(az account show --query tenantId -o tsv)
if [[ -z "$TENANT_ID" ]]; then
  echo "ERROR: Could not retrieve tenant ID"
  exit 1
fi
echo "✓ Tenant ID: $TENANT_ID"

# Get client ID from managed identity
echo "Looking for managed identity '$MANAGED_IDENTITY_NAME' in resource group '$RESOURCE_GROUP'..."
CLIENT_ID=$(az identity show \
  --name "$MANAGED_IDENTITY_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query clientId \
  -o tsv 2>/dev/null || echo "")

if [[ -z "$CLIENT_ID" ]]; then
  echo "ERROR: Could not find managed identity '$MANAGED_IDENTITY_NAME' in resource group '$RESOURCE_GROUP'"
  echo "Available managed identities in resource group:"
  az identity list --resource-group "$RESOURCE_GROUP" --query "[].{name:name, clientId:clientId}" -o table || true
  exit 1
fi
echo "✓ Client ID: $CLIENT_ID"

# --- Push to GitHub secrets ---
echo
echo "Setting GitHub repository secrets for $GITHUB_OWNER/$GITHUB_REPO..."

# Set AZURE_SUBSCRIPTION_ID
echo "Setting AZURE_SUBSCRIPTION_ID..."
echo "$SUBSCRIPTION_ID" | gh secret set AZURE_SUBSCRIPTION_ID --repo "$GITHUB_OWNER/$GITHUB_REPO"
echo "✓ AZURE_SUBSCRIPTION_ID set"

# Set AZURE_TENANT_ID
echo "Setting AZURE_TENANT_ID..."
echo "$TENANT_ID" | gh secret set AZURE_TENANT_ID --repo "$GITHUB_OWNER/$GITHUB_REPO"
echo "✓ AZURE_TENANT_ID set"

# Set AZURE_CLIENT_ID
echo "Setting AZURE_CLIENT_ID..."
echo "$CLIENT_ID" | gh secret set AZURE_CLIENT_ID --repo "$GITHUB_OWNER/$GITHUB_REPO"
echo "✓ AZURE_CLIENT_ID set"

echo
echo "✅ All secrets have been successfully set!"
echo
echo "GitHub repository secrets configured:"
echo "  AZURE_SUBSCRIPTION_ID: $SUBSCRIPTION_ID"
echo "  AZURE_TENANT_ID: $TENANT_ID" 
echo "  AZURE_CLIENT_ID: $CLIENT_ID"
echo
echo "You can now use these secrets in your GitHub Actions workflows for Azure OIDC authentication."