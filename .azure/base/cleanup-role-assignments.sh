#!/bin/bash

# Cleanup script for role assignments
# This script removes existing role assignments for the GitHub Actions identity
# to allow for clean redeployment

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Default values
SUBSCRIPTION_ID=""
NAME_PREFIX="privee"
ENVIRONMENT="dev"

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -s, --subscription-id ID    Azure subscription ID (optional, uses current if not specified)"
    echo "  -p, --name-prefix PREFIX    Name prefix for resources (default: privee)"
    echo "  -e, --environment ENV       Environment name (default: dev)"
    echo "  -h, --help                  Show this help message"
    echo ""
    echo "This script removes existing role assignments for the GitHub Actions identity"
    echo "to allow for clean redeployment when role assignment updates fail."
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -s|--subscription-id)
            SUBSCRIPTION_ID="$2"
            shift 2
            ;;
        -p|--name-prefix)
            NAME_PREFIX="$2"
            shift 2
            ;;
        -e|--environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Set subscription if provided
if [[ -n "$SUBSCRIPTION_ID" ]]; then
    log_info "Setting Azure subscription to: $SUBSCRIPTION_ID"
    az account set --subscription "$SUBSCRIPTION_ID"
fi

# Get current subscription
CURRENT_SUBSCRIPTION=$(az account show --query id -o tsv)
log_info "Working with subscription: $CURRENT_SUBSCRIPTION"

# Identity configuration
ADMIN_IDENTITY_NAME=$(echo "${NAME_PREFIX}-gha-admin-${ENVIRONMENT}" | tr '[:upper:]' '[:lower:]')

log_info "Looking for role assignments for identity: $ADMIN_IDENTITY_NAME"

# Find the principal ID of the managed identity
RESOURCE_GROUP_NAME="${NAME_PREFIX}-identity-rg"
PRINCIPAL_ID=""

if az group show --name "$RESOURCE_GROUP_NAME" &>/dev/null; then
    log_info "Found resource group: $RESOURCE_GROUP_NAME"
    
    if az identity show --resource-group "$RESOURCE_GROUP_NAME" --name "$ADMIN_IDENTITY_NAME" &>/dev/null; then
        PRINCIPAL_ID=$(az identity show --resource-group "$RESOURCE_GROUP_NAME" --name "$ADMIN_IDENTITY_NAME" --query principalId -o tsv)
        log_info "Found managed identity with principal ID: $PRINCIPAL_ID"
    else
        log_warning "Managed identity '$ADMIN_IDENTITY_NAME' not found in resource group '$RESOURCE_GROUP_NAME'"
    fi
else
    log_warning "Resource group '$RESOURCE_GROUP_NAME' not found"
fi

if [[ -z "$PRINCIPAL_ID" ]]; then
    log_warning "No managed identity found. Nothing to clean up."
    exit 0
fi

# Find and remove role assignments
log_info "Searching for role assignments for principal ID: $PRINCIPAL_ID"

ROLE_ASSIGNMENTS=$(az role assignment list --assignee "$PRINCIPAL_ID" --scope "/subscriptions/$CURRENT_SUBSCRIPTION" --query "[].{id:id,role:roleDefinitionName}" -o json)

if [[ "$ROLE_ASSIGNMENTS" == "[]" ]]; then
    log_info "No role assignments found for this identity."
    exit 0
fi

echo "Found the following role assignments:"
echo "$ROLE_ASSIGNMENTS" | jq -r '.[] | "- " + .role + " (" + .id + ")"'

echo ""
log_warning "This will remove ALL role assignments for the GitHub Actions identity."
read -p "Do you want to proceed? (y/N): " -n 1 -r
echo

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_info "Cleanup cancelled by user"
    exit 0
fi

# Remove role assignments
echo "$ROLE_ASSIGNMENTS" | jq -r '.[].id' | while read -r role_assignment_id; do
    log_info "Removing role assignment: $role_assignment_id"
    if az role assignment delete --ids "$role_assignment_id"; then
        log_success "Successfully removed role assignment"
    else
        log_error "Failed to remove role assignment: $role_assignment_id"
    fi
done

log_success "Role assignment cleanup completed!"
log_info "You can now re-run the deployment script."
