#!/bin/bash

# Base Infrastructure Deployment Script
# This script deploys the administrative User Managed Identity for GitHub Actions
# with Owner permissions at subscription level

set -euo pipefail

# Script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# Default values
LOCATION="West Europe"
SUBSCRIPTION_ID=""
PARAMETERS_FILE="$SCRIPT_DIR/admin-identity.parameters.json"
TEMPLATE_FILE="$SCRIPT_DIR/admin-identity.bicep"
MINIMAL_ROLE_TEMPLATE="$SCRIPT_DIR/minimal-role-assignment-permission.bicep"
MINIMAL_ROLE_PARAMETERS="$SCRIPT_DIR/minimal-role-assignment-permission.parameters.json"
DEPLOYMENT_NAME="admin-identity-$(date +%Y%m%d-%H%M%S)"
MINIMAL_ROLE_DEPLOYMENT_NAME="minimal-role-$(date +%Y%m%d-%H%M%S)"
CLEANUP_ROLE_ASSIGNMENTS=false

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
    echo "  -l, --location LOCATION     Azure region (default: West Europe)"
    echo "  -p, --parameters FILE       Parameters file path (default: admin-identity.parameters.json)"
    echo "  -n, --deployment-name NAME  Custom deployment name"
    echo "  -c, --cleanup-roles         Clean up existing role assignments before deployment"
    echo "  -h, --help                  Show this help message"
    echo ""
    echo "Environment Variables (optional):"
    echo "  AZURE_SUBSCRIPTION_ID       Azure subscription ID"
    echo ""
    echo "Note: If no subscription is specified via --subscription-id or AZURE_SUBSCRIPTION_ID,"
    echo "      the script will use the currently active Azure CLI subscription."
    echo ""
    echo "The --cleanup-roles option will remove existing role assignments for the GitHub Actions"
    echo "identity before redeployment, which helps resolve role assignment update conflicts."
    echo ""
    echo "Examples:"
    echo "  $0                                                    # Use current subscription"
    echo "  $0 --subscription-id 12345678-1234-1234-1234-123456789012"
    echo "  $0 -s 12345678-1234-1234-1234-123456789012 -l 'East US'"
    echo "  $0 --cleanup-roles                                   # Clean up role assignments before deployment"
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

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -s|--subscription-id)
            SUBSCRIPTION_ID="$2"
            shift 2
            ;;
        -l|--location)
            LOCATION="$2"
            shift 2
            ;;
        -p|--parameters)
            PARAMETERS_FILE="$2"
            shift 2
            ;;
        -n|--deployment-name)
            DEPLOYMENT_NAME="$2"
            shift 2
            ;;
        -c|--cleanup-roles)
            CLEANUP_ROLE_ASSIGNMENTS=true
            shift
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

if [[ ! -f "$PARAMETERS_FILE" ]]; then
    log_error "Parameters file not found: $PARAMETERS_FILE"
    exit 1
fi

if [[ ! -f "$TEMPLATE_FILE" ]]; then
    log_error "Template file not found: $TEMPLATE_FILE"
    exit 1
fi

if [[ ! -f "$MINIMAL_ROLE_TEMPLATE" ]]; then
    log_error "Minimal role template file not found: $MINIMAL_ROLE_TEMPLATE"
    exit 1
fi

if [[ ! -f "$MINIMAL_ROLE_PARAMETERS" ]]; then
    log_error "Minimal role parameters file not found: $MINIMAL_ROLE_PARAMETERS"
    exit 1
fi

log_info "Starting base infrastructure deployment..."
log_info "This will deploy:"
log_info "1. Custom role with minimal role assignment permissions"
log_info "2. GitHub Actions managed identity with Contributor + custom role"
log_info "Subscription: $SUBSCRIPTION_ID"
log_info "Location: $LOCATION"
log_info "Admin Identity Parameters: $PARAMETERS_FILE"
log_info "Minimal Role Parameters: $MINIMAL_ROLE_PARAMETERS"
log_info "Deployment: $DEPLOYMENT_NAME"

# Check if logged into Azure CLI
if ! az account show >/dev/null 2>&1; then
    log_error "Not logged into Azure CLI. Please run 'az login' first."
    exit 1
fi

# Set the subscription (this will also verify it exists and we have access)
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

# Validate templates
log_info "Validating minimal role Bicep template..."
if ! az deployment sub validate \
    --location "$LOCATION" \
    --template-file "$MINIMAL_ROLE_TEMPLATE" \
    --parameters "@$MINIMAL_ROLE_PARAMETERS" >/dev/null; then
    log_error "Minimal role template validation failed"
    exit 1
fi
log_success "Minimal role template validation passed"

log_info "Validating admin identity Bicep template..."
if ! az deployment sub validate \
    --location "$LOCATION" \
    --template-file "$TEMPLATE_FILE" \
    --parameters "@$PARAMETERS_FILE" >/dev/null; then
    log_error "Admin identity template validation failed"
    exit 1
fi
log_success "Admin identity template validation passed"

# Preview deployments (what-if)
log_info "Generating minimal role deployment preview..."
if ! az deployment sub what-if \
    --location "$LOCATION" \
    --template-file "$MINIMAL_ROLE_TEMPLATE" \
    --parameters "@$MINIMAL_ROLE_PARAMETERS" \
    --name "$MINIMAL_ROLE_DEPLOYMENT_NAME"; then
    log_warning "Minimal role preview generation failed, but continuing..."
fi

log_info "Generating admin identity deployment preview..."
if ! az deployment sub what-if \
    --location "$LOCATION" \
    --template-file "$TEMPLATE_FILE" \
    --parameters "@$PARAMETERS_FILE" \
    --name "$DEPLOYMENT_NAME"; then
    log_warning "Admin identity preview generation failed, but continuing..."
fi

# Confirm deployment
echo ""
read -p "Do you want to proceed with both deployments (custom role + admin identity)? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_info "Deployment cancelled by user"
    exit 0
fi

# Cleanup existing role assignments if requested
if [[ "$CLEANUP_ROLE_ASSIGNMENTS" == "true" ]]; then
    log_info "Step 0: Cleaning up existing role assignments..."
    CLEANUP_SCRIPT="$SCRIPT_DIR/cleanup-role-assignments.sh"
    if [[ -f "$CLEANUP_SCRIPT" ]]; then
        if bash "$CLEANUP_SCRIPT" --subscription-id "$SUBSCRIPTION_ID"; then
            log_success "Role assignment cleanup completed!"
        else
            log_warning "Role assignment cleanup failed, but continuing with deployment..."
        fi
    else
        log_warning "Cleanup script not found at $CLEANUP_SCRIPT, skipping cleanup..."
    fi
    echo
fi

# Deploy custom role first
log_info "Step 1: Deploying custom role with minimal permissions..."
if az deployment sub create \
    --location "$LOCATION" \
    --template-file "$MINIMAL_ROLE_TEMPLATE" \
    --parameters "@$MINIMAL_ROLE_PARAMETERS" \
    --name "$MINIMAL_ROLE_DEPLOYMENT_NAME" \
    --output table; then
    
    log_success "Custom role deployment completed successfully!"
else
    log_error "Custom role deployment failed!"
    exit 1
fi

# Wait for role propagation
log_info "Waiting 10 seconds for role propagation..."
sleep 10

# Deploy admin identity
log_info "Step 2: Deploying admin identity with custom role..."
if az deployment sub create \
    --location "$LOCATION" \
    --template-file "$TEMPLATE_FILE" \
    --parameters "@$PARAMETERS_FILE" \
    --name "$DEPLOYMENT_NAME" \
    --output table; then
    
    log_success "Admin identity deployment completed successfully!"
    
    # Get outputs
    log_info "Retrieving deployment outputs..."
    OUTPUTS=$(az deployment sub show --name "$DEPLOYMENT_NAME" --query properties.outputs --output json)
    
    if [[ -n "$OUTPUTS" && "$OUTPUTS" != "null" ]]; then
        CLIENT_ID=$(echo "$OUTPUTS" | jq -r '.clientId.value // empty')
        PRINCIPAL_ID=$(echo "$OUTPUTS" | jq -r '.principalId.value // empty')
        RESOURCE_GROUP=$(echo "$OUTPUTS" | jq -r '.resourceGroupName.value // empty')
        FEDERATED_SUBJECT=$(echo "$OUTPUTS" | jq -r '.federatedSubject.value // empty')
        
        echo ""
        echo "=================================================="
        echo "🎉 DEPLOYMENT SUCCESSFUL!"
        echo "=================================================="
        echo "Client ID:          $CLIENT_ID"
        echo "Principal ID:       $PRINCIPAL_ID"
        echo "Resource Group:     $RESOURCE_GROUP"
        echo "Federated Subject:  $FEDERATED_SUBJECT"
        echo "=================================================="
        echo ""
        echo "🔑 GITHUB SECRETS TO SET:"
        echo "=================================================="
        echo "AZURE_CLIENT_ID: $CLIENT_ID"
        echo "AZURE_TENANT_ID: $(az account show --query tenantId -o tsv)"
        echo "AZURE_SUBSCRIPTION_ID: $SUBSCRIPTION_ID"
        echo "=================================================="
        echo ""
        echo "🔐 ROLES ASSIGNED:"
        echo "=================================================="
        echo "✅ Contributor (resource management)"
        echo "✅ Custom: Minimal Role Assigner (Microsoft.Authorization/roleAssignments/write)"
        echo "=================================================="
        echo ""
        log_info "The managed identity now has minimal permissions to fix the role assignment error"
        log_info "Add the GitHub secrets above to your repository for OIDC authentication"
    fi
    
else
    log_error "Admin identity deployment failed!"
    exit 1
fi
