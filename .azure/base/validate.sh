#!/bin/bash

# Validation script for base infrastructure templates
# This script validates the Bicep templates without deploying them

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
TEMPLATE_FILE="$SCRIPT_DIR/admin-identity.bicep"
PARAMETERS_FILE="$SCRIPT_DIR/admin-identity.parameters.json"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Check if files exist
if [[ ! -f "$TEMPLATE_FILE" ]]; then
    log_error "Template file not found: $TEMPLATE_FILE"
    exit 1
fi

if [[ ! -f "$PARAMETERS_FILE" ]]; then
    log_error "Parameters file not found: $PARAMETERS_FILE"
    exit 1
fi

# Check Azure CLI
if ! command -v az >/dev/null 2>&1; then
    log_error "Azure CLI not found. Please install Azure CLI."
    exit 1
fi

if ! az account show >/dev/null 2>&1; then
    log_error "Not logged into Azure CLI. Please run 'az login' first."
    exit 1
fi

log_info "Validating Bicep templates..."

# Install/update Bicep
log_info "Ensuring Bicep CLI is available..."
az bicep install >/dev/null 2>&1 || true
az bicep upgrade >/dev/null 2>&1 || true

# Build template
log_info "Building main template..."
if az bicep build --file "$TEMPLATE_FILE" >/dev/null 2>&1; then
    log_success "Main template builds successfully"
else
    log_error "Main template build failed"
    exit 1
fi

# Build identity module
IDENTITY_MODULE="$SCRIPT_DIR/identity.bicep"
if [[ -f "$IDENTITY_MODULE" ]]; then
    log_info "Building identity module..."
    if az bicep build --file "$IDENTITY_MODULE" >/dev/null 2>&1; then
        log_success "Identity module builds successfully"
    else
        log_error "Identity module build failed"
        exit 1
    fi
fi

# Validate parameters file
log_info "Validating parameters file..."
if jq empty "$PARAMETERS_FILE" >/dev/null 2>&1; then
    log_success "Parameters file is valid JSON"
else
    log_error "Parameters file is not valid JSON"
    exit 1
fi

# Validate template with parameters
log_info "Validating template with parameters..."
if az deployment sub validate \
    --location "West Europe" \
    --template-file "$TEMPLATE_FILE" \
    --parameters "@$PARAMETERS_FILE" \
    --output none >/dev/null 2>&1; then
    log_success "Template validation passed"
else
    log_error "Template validation failed"
    echo "Running validation again with detailed output:"
    az deployment sub validate \
        --location "West Europe" \
        --template-file "$TEMPLATE_FILE" \
        --parameters "@$PARAMETERS_FILE"
    exit 1
fi

echo ""
log_success "All validations passed! Templates are ready for deployment."
echo ""
echo "To deploy:"
echo "  ./deploy.sh --subscription-id YOUR_SUBSCRIPTION_ID"
