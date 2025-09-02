#!/bin/bash

# This script deletes the specified Azure Resource Groups.
# WARNING: This action is irreversible.

set -e

# List of Resource Groups to delete
resource_groups=(
  "MC_privee-dev-rg_privee-aks_northeurope"
  "NetworkWatcherRG"
  "privee-dev-kv-rg"
  "privee-dev-rg"
)

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
