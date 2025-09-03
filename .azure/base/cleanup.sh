#!/bin/bash

# Cleanup script for base infrastructure
# This script removes the User Managed Identity and its resource group
# WARNING: This will permanently delete the identity and all associated role assignments

set -euo pipefail

# Script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# Default values
SUBSCRIPTION_ID=""
PARAMETERS_FILE="$SCRIPT_DIR/admin-identity.parameters.json"
RESOURCE_GROUP_NAME=""
FORCE_DELETE=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -s, --subscription-id ID    Azure subscription ID (optional, uses current if not specified)"
    echo "  -r, --resource-group NAME   Resource group name to delete (optional, reads from parameters)"
    echo "  -f, --force                 Skip confirmation prompts"
    echo "  -p, --parameters FILE       Parameters file path (default: admin-identity.parameters.json)"
    echo "  -h, --help                  Show this help message"
    echo ""
    echo "Environment Variables (optional):"
    echo "  AZURE_SUBSCRIPTION_ID       Azure subscription ID"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Interactive cleanup using current subscription"
    echo "  $0 --force                           # Non-interactive cleanup"
    echo "  $0 -r privee-identity-rg --force     # Delete specific resource group"
    echo ""
    echo "⚠️  WARNING: This will permanently delete the Managed Identity and all its role assignments!"
}

log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

confirm_action() {
    if [[ "$FORCE_DELETE" == "true" ]]; then
        return 0
    fi
    
    local message="$1"
    echo ""
    read -p "$message (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        return 1
    fi
    return 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -s|--subscription-id)
            SUBSCRIPTION_ID="$2"
            shift 2
            ;;
        -r|--resource-group)
            RESOURCE_GROUP_NAME="$2"
            shift 2
            ;;
        -f|--force)
            FORCE_DELETE=true
            shift
            ;;
        -p|--parameters)
            PARAMETERS_FILE="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Use environment variable if subscription not provided
if [[ -z "$SUBSCRIPTION_ID" && -n "${AZURE_SUBSCRIPTION_ID:-}" ]]; then
    SUBSCRIPTION_ID="$AZURE_SUBSCRIPTION_ID"
fi

# If still no subscription ID, try to get it from current Azure CLI context
if [[ -z "$SUBSCRIPTION_ID" ]]; then
    log_info "No subscription specified, checking current Azure CLI context..."
    
    # Check if logged into Azure CLI
    if ! az account show >/dev/null 2>&1; then
        log_error "Not logged into Azure CLI. Please run 'az login' first."
        exit 1
    fi
    
    # Get current subscription ID
    SUBSCRIPTION_ID=$(az account show --query id --output tsv 2>/dev/null)
    
    if [[ -n "$SUBSCRIPTION_ID" ]]; then
        log_info "Using current subscription: $SUBSCRIPTION_ID"
    else
        log_error "Could not determine current subscription ID. Please specify --subscription-id or set AZURE_SUBSCRIPTION_ID environment variable."
        usage
        exit 1
    fi
fi

# If resource group not specified, try to read from parameters file
if [[ -z "$RESOURCE_GROUP_NAME" ]]; then
    if [[ -f "$PARAMETERS_FILE" ]]; then
        log_info "Reading resource group name from parameters file..."
        RESOURCE_GROUP_NAME=$(jq -r '.parameters.identityResourceGroupName.value // empty' "$PARAMETERS_FILE" 2>/dev/null || echo "")
        
        if [[ -z "$RESOURCE_GROUP_NAME" ]]; then
            # Try alternative parameter name structure
            NAME_PREFIX=$(jq -r '.parameters.namePrefix.value // empty' "$PARAMETERS_FILE" 2>/dev/null || echo "")
            if [[ -n "$NAME_PREFIX" ]]; then
                RESOURCE_GROUP_NAME="${NAME_PREFIX}-identity-rg"
                log_info "Inferred resource group name: $RESOURCE_GROUP_NAME"
            fi
        fi
    fi
fi

# Validate required parameters
if [[ -z "$RESOURCE_GROUP_NAME" ]]; then
    log_error "Resource group name is required. Use --resource-group or ensure it's in the parameters file."
    usage
    exit 1
fi

# Check if logged into Azure CLI
if ! az account show >/dev/null 2>&1; then
    log_error "Not logged into Azure CLI. Please run 'az login' first."
    exit 1
fi

# Set the subscription
log_info "Setting active subscription..."
if ! az account set --subscription "$SUBSCRIPTION_ID"; then
    log_error "Failed to set subscription: $SUBSCRIPTION_ID"
    log_error "Please verify the subscription ID and that you have access to it."
    exit 1
fi

# Display current subscription info for confirmation
CURRENT_SUB_INFO=$(az account show --query "{name:name, id:id, tenantId:tenantId}" --output json)
SUB_NAME=$(echo "$CURRENT_SUB_INFO" | jq -r '.name')
SUB_ID=$(echo "$CURRENT_SUB_INFO" | jq -r '.id')
TENANT_ID=$(echo "$CURRENT_SUB_INFO" | jq -r '.tenantId')

log_info "Active subscription: $SUB_NAME ($SUB_ID)"
log_info "Tenant: $TENANT_ID"

echo ""
log_warning "CLEANUP SUMMARY"
log_warning "==============="
log_warning "Resource Group: $RESOURCE_GROUP_NAME"
log_warning "Subscription: $SUB_NAME ($SUB_ID)"
log_warning ""
log_warning "This will DELETE:"
log_warning "• User Managed Identity and its federated credentials"
log_warning "• All role assignments associated with the identity"
log_warning "• The entire resource group and all its contents"
log_warning ""
log_warning "This action is IRREVERSIBLE!"

# Check if resource group exists
log_info "Checking if resource group exists..."
if ! az group show --name "$RESOURCE_GROUP_NAME" >/dev/null 2>&1; then
    log_warning "Resource group '$RESOURCE_GROUP_NAME' does not exist or you don't have access to it."
    exit 0
fi
log_success "Resource group '$RESOURCE_GROUP_NAME' found"

# Get identity information before deletion
log_info "Retrieving identity information..."
IDENTITY_INFO=$(az identity list --resource-group "$RESOURCE_GROUP_NAME" --query "[].{name:name, clientId:clientId, principalId:principalId}" --output json 2>/dev/null || echo "[]")

if [[ "$IDENTITY_INFO" != "[]" && "$IDENTITY_INFO" != "null" ]]; then
    echo ""
    echo "🔍 IDENTITIES TO BE DELETED:"
    echo "$IDENTITY_INFO" | jq -r '.[] | "• Name: \(.name)\n  Client ID: \(.clientId)\n  Principal ID: \(.principalId)\n"'
    echo ""
fi

# Final confirmation
if ! confirm_action "⚠️  Are you sure you want to delete the resource group '$RESOURCE_GROUP_NAME' and all its contents?"; then
    log_info "Cleanup cancelled by user"
    exit 0
fi

# Delete the resource group
log_info "Deleting resource group: $RESOURCE_GROUP_NAME"
log_warning "This may take several minutes..."

if az group delete --name "$RESOURCE_GROUP_NAME" --yes --no-wait; then
    log_success "Resource group deletion initiated successfully!"
    log_info "The deletion is running in the background."
    log_info "You can check the status with:"
    echo "  az group show --name '$RESOURCE_GROUP_NAME' --query 'properties.provisioningState'"
    
    echo ""
    echo "=================================================="
    echo "🗑️  CLEANUP INITIATED"
    echo "=================================================="
    echo "Resource Group: $RESOURCE_GROUP_NAME"
    echo "Status: Deletion in progress"
    echo "=================================================="
    echo ""
    log_info "The User Managed Identity and all its role assignments will be removed."
    log_info "You'll need to update your GitHub repository secrets if you plan to redeploy."
    
else
    log_error "Failed to delete resource group: $RESOURCE_GROUP_NAME"
    log_error "Please check your permissions and try again."
    exit 1
fi

echo ""
log_success "Cleanup script completed successfully!"
log_info "To verify deletion is complete, run:"
echo "  az group show --name '$RESOURCE_GROUP_NAME'"
log_info "(This should return a 'ResourceGroupNotFound' error when deletion is complete)"
