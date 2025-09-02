#!/bin/bash

# Script to find, cancel, and delete all active deployments in a subscription
# Prerequisites: User must be logged in to Azure CLI with appropriate permissions

set -e

echo "Starting deployment cleanup process..."
echo "========================================="

# Get the current subscription ID for reference
subscription_id=$(az account show --query id -o tsv)
echo "Current subscription: $subscription_id"
echo ""

# Counter for tracking operations
total_deployments=0
cancelled_deployments=0
deleted_deployments=0

# List all resource groups in the subscription
echo "Fetching all resource groups..."
resource_groups=$(az group list --query "[].name" -o tsv)

if [ -z "$resource_groups" ]; then
    echo "No resource groups found in the subscription."
    exit 0
fi

echo "Found resource groups: $(echo "$resource_groups" | wc -l)"
echo ""

for rg in $resource_groups; do
    echo "Processing resource group: $rg"
    echo "-----------------------------------"
    
    # List all deployments in the resource group (both running and completed)
    deployments=$(az deployment group list --resource-group "$rg" --query "[].name" -o tsv 2>/dev/null || true)
    
    if [ -z "$deployments" ]; then
        echo "  No deployments found in resource group $rg"
        echo ""
        continue
    fi
    
    for deployment in $deployments; do
        total_deployments=$((total_deployments + 1))
        
        # Get deployment status
        status=$(az deployment group show --resource-group "$rg" --name "$deployment" --query "properties.provisioningState" -o tsv 2>/dev/null || echo "Unknown")
        
        echo "  Processing deployment: $deployment (Status: $status)"
        
        # Cancel deployment if it's running
        if [ "$status" = "Running" ] || [ "$status" = "Accepted" ]; then
            echo "    Cancelling running deployment..."
            if az deployment group cancel --resource-group "$rg" --name "$deployment" 2>/dev/null; then
                cancelled_deployments=$((cancelled_deployments + 1))
                echo "    ✓ Deployment cancelled successfully"
            else
                echo "    ⚠ Failed to cancel deployment (may have completed)"
            fi
        else
            echo "    Deployment not running, skipping cancellation"
        fi
        
        # Delete the deployment
        echo "    Deleting deployment..."
        if az deployment group delete --resource-group "$rg" --name "$deployment" --no-wait 2>/dev/null; then
            deleted_deployments=$((deleted_deployments + 1))
            echo "    ✓ Deployment deletion initiated"
        else
            echo "    ⚠ Failed to delete deployment"
        fi
    done
    
    echo ""
done

echo "========================================="
echo "Deployment cleanup summary:"
echo "  Total deployments processed: $total_deployments"
echo "  Deployments cancelled: $cancelled_deployments"
echo "  Deployments deleted: $deleted_deployments"
echo ""
echo "Note: Deletion operations may take some time to complete."
echo "Use 'az deployment group list --resource-group <rg-name>' to verify cleanup."
