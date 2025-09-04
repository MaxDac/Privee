#!/bin/bash

# This script deletes the specified Azure Resource Groups.
# WARNING: This action is irreversible.

set -e

# Parse command line arguments
DELETE_ADMIN_IDENTITY=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --delete-admin-identity)
      DELETE_ADMIN_IDENTITY=true
      shift
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--delete-admin-identity]"
      exit 1
      ;;
  esac
done

# List of Resource Groups to delete
resource_groups=(
  "MC_privee-dev-rg_privee-aks_northeurope"
  "NetworkWatcherRG"
  "privee-dev-kv-rg"
  "privee-dev-rg"
)

# Conditionally add the identity resource group
if [ "$DELETE_ADMIN_IDENTITY" = true ]; then
  resource_groups+=("privee-identity-rg")
  echo "WARNING: Admin identity resource group will be deleted!"
else
  echo "Admin identity resource group will be preserved (use --delete-admin-identity to delete it)"
fi

for rg in "${resource_groups[@]}"; do
  echo "Attempting to delete Resource Group: $rg"
  if az group show --name "$rg" &>/dev/null; then
    echo "Resource Group '$rg' found. Issuing delete command..."
    az group delete --name "$rg" --yes --no-wait
  else
    echo "Resource Group '$rg' not found. Skipping."
  fi
done

echo "Deletion commands have been issued for the specified resource groups."
echo "It may take some time for the deletions to complete in Azure."
