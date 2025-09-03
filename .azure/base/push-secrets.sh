#!/bin/bash

# GitHub Secrets Push Script
# This script extracts Managed Identity information and pushes secrets to GitHub repository

set -euo pipefail

# Script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# Default values
SUBSCRIPTION_ID=""
DEPLOYMENT_NAME=""
GITHUB_REPO="MaxDac/Privee"
DRY_RUN=false
FORCE_UPDATE=false

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
    echo "  -d, --deployment-name NAME  Specific deployment name to get outputs from"
    echo "  -r, --repo OWNER/REPO       GitHub repository (default: MaxDac/Privee)"
    echo "  -n, --dry-run               Show what would be set without actually setting secrets"
    echo "  -f, --force                 Update secrets even if they already exist"
    echo "  -h, --help                  Show this help message"
    echo ""
    echo "Environment Variables (optional):"
    echo "  AZURE_SUBSCRIPTION_ID       Azure subscription ID"
    echo "  GITHUB_TOKEN                GitHub personal access token (required for gh CLI)"
    echo ""
    echo "Prerequisites:"
    echo "  - Azure CLI logged in with access to the subscription"
    echo "  - GitHub CLI (gh) installed and authenticated"
    echo "  - Successful deployment of admin-identity.bicep"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Use latest deployment from current subscription"
    echo "  $0 --dry-run                         # Preview what would be set"
    echo "  $0 --deployment-name admin-identity-20240902-143022"
    echo "  $0 --repo MyOrg/MyRepo --force       # Different repo, force update"
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
        -d|--deployment-name)
            DEPLOYMENT_NAME="$2"
            shift 2
            ;;
        -r|--repo)
            GITHUB_REPO="$2"
            shift 2
            ;;
        -n|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -f|--force)
            FORCE_UPDATE=true
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
        log_error "Could not determine current subscription ID."
        exit 1
    fi
fi

# Check prerequisites
log_info "Checking prerequisites..."

# Check Azure CLI
if ! command -v az >/dev/null 2>&1; then
    log_error "Azure CLI not found. Please install Azure CLI."
    exit 1
fi

if ! az account show >/dev/null 2>&1; then
    log_error "Not logged into Azure CLI. Please run 'az login' first."
    exit 1
fi

# Check GitHub CLI
if ! command -v gh >/dev/null 2>&1; then
    log_error "GitHub CLI (gh) not found. Please install GitHub CLI."
    log_error "Install with: https://cli.github.com/"
    exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
    log_error "GitHub CLI not authenticated. Please run 'gh auth login' first."
    exit 1
fi

# Check jq
if ! command -v jq >/dev/null 2>&1; then
    log_error "jq not found. Please install jq for JSON processing."
    exit 1
fi

log_success "All prerequisites met"

# Set the subscription
log_info "Setting active subscription..."
if ! az account set --subscription "$SUBSCRIPTION_ID"; then
    log_error "Failed to set subscription: $SUBSCRIPTION_ID"
    exit 1
fi

# Get deployment information
if [[ -z "$DEPLOYMENT_NAME" ]]; then
    log_info "Finding latest admin-identity deployment..."
    DEPLOYMENT_NAME=$(az deployment sub list \
        --query "[?contains(name, 'admin-identity')] | sort_by(@, &properties.timestamp) | [-1].name" \
        --output tsv 2>/dev/null || echo "")
    
    if [[ -z "$DEPLOYMENT_NAME" ]]; then
        log_error "No admin-identity deployment found in subscription."
        log_error "Please specify --deployment-name or ensure the deployment exists."
        exit 1
    fi
    
    log_info "Found deployment: $DEPLOYMENT_NAME"
fi

# Get deployment outputs
log_info "Retrieving deployment outputs..."
OUTPUTS=$(az deployment sub show --name "$DEPLOYMENT_NAME" --query properties.outputs --output json 2>/dev/null)

if [[ -z "$OUTPUTS" || "$OUTPUTS" == "null" ]]; then
    log_error "No outputs found for deployment: $DEPLOYMENT_NAME"
    log_error "Please ensure the deployment completed successfully."
    exit 1
fi

# Extract values
CLIENT_ID=$(echo "$OUTPUTS" | jq -r '.clientId.value // empty')
TENANT_ID=$(az account show --query tenantId --output tsv)

if [[ -z "$CLIENT_ID" ]]; then
    log_error "Could not extract Client ID from deployment outputs."
    exit 1
fi

if [[ -z "$TENANT_ID" ]]; then
    log_error "Could not extract Tenant ID from Azure CLI."
    exit 1
fi

# Display summary
echo ""
log_info "SECRETS TO BE SET:"
echo "=================================================="
echo "Repository: $GITHUB_REPO"
echo "CONTRIBUTOR_SUBSCRIPTION_ID: $SUBSCRIPTION_ID"
echo "CONTRIBUTOR_TENANT_ID: $TENANT_ID"
echo "CONTRIBUTOR_CLIENT_ID: $CLIENT_ID"
echo "=================================================="
echo ""

# Check if secrets already exist (if not forcing update)
if [[ "$FORCE_UPDATE" != "true" && "$DRY_RUN" != "true" ]]; then
    log_info "Checking existing secrets..."
    
    EXISTING_SECRETS=$(gh secret list --repo "$GITHUB_REPO" --json name --jq '.[].name' 2>/dev/null || echo "")
    
    declare -a CONFLICTS=()
    for secret in "CONTRIBUTOR_SUBSCRIPTION_ID" "CONTRIBUTOR_TENANT_ID" "CONTRIBUTOR_CLIENT_ID"; do
        if echo "$EXISTING_SECRETS" | grep -q "^$secret$"; then
            CONFLICTS+=("$secret")
        fi
    done
    
    if [[ ${#CONFLICTS[@]} -gt 0 ]]; then
        log_warning "The following secrets already exist:"
        printf '  - %s\n' "${CONFLICTS[@]}"
        echo ""
        echo "Use --force to update existing secrets or --dry-run to preview."
        read -p "Do you want to update existing secrets? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Operation cancelled by user"
            exit 0
        fi
    fi
fi

# Set secrets
if [[ "$DRY_RUN" == "true" ]]; then
    log_info "DRY RUN - Would set the following secrets:"
    echo "  gh secret set CONTRIBUTOR_SUBSCRIPTION_ID --repo $GITHUB_REPO --body '$SUBSCRIPTION_ID'"
    echo "  gh secret set CONTRIBUTOR_TENANT_ID --repo $GITHUB_REPO --body '$TENANT_ID'"
    echo "  gh secret set CONTRIBUTOR_CLIENT_ID --repo $GITHUB_REPO --body '$CLIENT_ID'"
    log_success "Dry run completed successfully!"
    exit 0
fi

log_info "Setting GitHub secrets..."

# Set each secret
if gh secret set CONTRIBUTOR_SUBSCRIPTION_ID --repo "$GITHUB_REPO" --body "$SUBSCRIPTION_ID"; then
    log_success "Set CONTRIBUTOR_SUBSCRIPTION_ID"
else
    log_error "Failed to set CONTRIBUTOR_SUBSCRIPTION_ID"
    exit 1
fi

if gh secret set CONTRIBUTOR_TENANT_ID --repo "$GITHUB_REPO" --body "$TENANT_ID"; then
    log_success "Set CONTRIBUTOR_TENANT_ID"
else
    log_error "Failed to set CONTRIBUTOR_TENANT_ID"
    exit 1
fi

if gh secret set CONTRIBUTOR_CLIENT_ID --repo "$GITHUB_REPO" --body "$CLIENT_ID"; then
    log_success "Set CONTRIBUTOR_CLIENT_ID"
else
    log_error "Failed to set CONTRIBUTOR_CLIENT_ID"
    exit 1
fi

echo ""
echo "=================================================="
echo "🎉 GITHUB SECRETS SET SUCCESSFULLY!"
echo "=================================================="
echo "Repository: $GITHUB_REPO"
echo "Secrets:"
echo "  ✅ CONTRIBUTOR_SUBSCRIPTION_ID"
echo "  ✅ CONTRIBUTOR_TENANT_ID"
echo "  ✅ CONTRIBUTOR_CLIENT_ID"
echo "=================================================="
echo ""
log_success "Your GitHub Actions can now authenticate with Azure using OIDC!"
echo ""
log_info "Example GitHub Actions usage:"
echo "  - name: Azure login (OIDC)"
echo "    uses: azure/login@v2"
echo "    with:"
echo "      client-id: \${{ secrets.CONTRIBUTOR_CLIENT_ID }}"
echo "      tenant-id: \${{ secrets.CONTRIBUTOR_TENANT_ID }}"
echo "      subscription-id: \${{ secrets.CONTRIBUTOR_SUBSCRIPTION_ID }}"
