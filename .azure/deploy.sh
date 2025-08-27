#!/bin/bash

# Exit on error
set -e

# Set default values
LOCATION="eastus"

# Parse command-line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -l|--location) LOCATION="$2"; shift ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

# Check if logged in to Azure
if ! az account show > /dev/null 2>&1; then
    echo "You are not logged in to Azure. Please run 'az login' to authenticate."
    exit 1
fi

echo "Building Bicep template..."
az bicep build --file "$(dirname "$0")/main-subscription.bicep" --outfile "$(dirname "$0")/main-subscription.json"

echo "Starting deployment to subscription..."

# Deploy the compiled ARM template
az deployment sub create \
    --name "privee-main-deployment" \
    --location "northeurope" \
    --template-file "$(dirname "$0")/main-subscription.json" \
    --parameters "$(dirname "$0")/main.parameters.json" \
    --debug

echo "Deployment completed successfully."
