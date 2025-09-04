#!/bin/bash
# Deploy minimal role assignment permission fix
# This script creates a custom role with only the specific permission mentioned in the error
# and then deploys the admin identity with that minimal permission

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MINIMAL_ROLE_TEMPLATE="${SCRIPT_DIR}/minimal-role-assignment-permission.bicep"
ADMIN_IDENTITY_TEMPLATE="${SCRIPT_DIR}/admin-identity.bicep"
ADMIN_IDENTITY_PARAMETERS="${SCRIPT_DIR}/admin-identity.parameters.json"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Deploying Minimal Role Assignment Permission Fix ===${NC}"
echo "This creates a custom role with only Microsoft.Authorization/roleAssignments/write permission"
echo

# Check if parameters file exists
if [[ ! -f "${ADMIN_IDENTITY_PARAMETERS}" ]]; then
    echo -e "${RED}Error: Parameters file ${ADMIN_IDENTITY_PARAMETERS} not found${NC}"
    exit 1
fi

# Validate Azure login
if ! az account show >/dev/null 2>&1; then
    echo -e "${RED}Error: Not logged in to Azure CLI${NC}"
    echo -e "${YELLOW}Please run: az login${NC}"
    exit 1
fi

# Get current subscription info
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
SUBSCRIPTION_NAME=$(az account show --query name -o tsv)

echo -e "${YELLOW}Current subscription:${NC} ${SUBSCRIPTION_NAME} (${SUBSCRIPTION_ID})"

# Extract parameters for the custom role deployment
NAME_PREFIX=$(jq -r '.parameters.namePrefix.value' "${ADMIN_IDENTITY_PARAMETERS}")
ENVIRONMENT=$(jq -r '.parameters.environment.value' "${ADMIN_IDENTITY_PARAMETERS}")

if [[ "${NAME_PREFIX}" == "null" || "${ENVIRONMENT}" == "null" ]]; then
    echo -e "${RED}Error: Could not extract namePrefix or environment from ${ADMIN_IDENTITY_PARAMETERS}${NC}"
    exit 1
fi

echo -e "${YELLOW}Configuration:${NC}"
echo "  Name Prefix: ${NAME_PREFIX}"
echo "  Environment: ${ENVIRONMENT}"
echo "  Location: northeurope"
echo

# Prompt for confirmation
read -p "Deploy minimal role assignment permission fix? [y/N]: " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Deployment cancelled${NC}"
    exit 0
fi

# Step 1: Deploy the minimal custom role
echo -e "${GREEN}Step 1: Creating minimal custom role...${NC}"
CUSTOM_ROLE_DEPLOYMENT="minimal-role-$(date +%Y%m%d-%H%M%S)"

az deployment sub create \
    --location "northeurope" \
    --name "${CUSTOM_ROLE_DEPLOYMENT}" \
    --template-file "${MINIMAL_ROLE_TEMPLATE}" \
    --parameters namePrefix="${NAME_PREFIX}" environment="${ENVIRONMENT}" \
    --verbose

if [[ $? -ne 0 ]]; then
    echo -e "${RED}✗ Failed to create custom role${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Custom role created successfully${NC}"

# Wait a moment for role propagation
echo -e "${YELLOW}Waiting 10 seconds for role propagation...${NC}"
sleep 10

# Step 2: Deploy the admin identity with the custom role
echo -e "${GREEN}Step 2: Deploying admin identity with minimal role assignment permission...${NC}"
ADMIN_IDENTITY_DEPLOYMENT="admin-identity-$(date +%Y%m%d-%H%M%S)"

az deployment sub create \
    --location "northeurope" \
    --name "${ADMIN_IDENTITY_DEPLOYMENT}" \
    --template-file "${ADMIN_IDENTITY_TEMPLATE}" \
    --parameters @"${ADMIN_IDENTITY_PARAMETERS}" \
    --verbose

# Check deployment status
if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}✓ Admin identity deployed successfully with minimal role assignment permission${NC}"
    echo
    echo -e "${GREEN}=== Deployment Summary ===${NC}"
    az deployment sub show \
        --name "${ADMIN_IDENTITY_DEPLOYMENT}" \
        --query "properties.outputs.permissionsSummary.value" \
        --output table
    echo
    echo -e "${YELLOW}What was deployed:${NC}"
    echo "1. Custom role: '${NAME_PREFIX}-minimal-role-assigner-${ENVIRONMENT}'"
    echo "   - Permissions: Microsoft.Authorization/roleAssignments/write, read"
    echo "2. GitHub Actions managed identity with:"
    echo "   - Contributor role (resource management)"
    echo "   - Custom minimal role assigner role (only the specific permission from the error)"
    echo
    echo -e "${GREEN}The GitHub Actions pipeline should now work without role assignment errors!${NC}"
else
    echo -e "${RED}✗ Admin identity deployment failed${NC}"
    exit 1
fi
