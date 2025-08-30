#!/bin/bash

# This script purges all soft-deleted Key Vaults in the current subscription.

echo "Checking for necessary permissions..."
# The permission 'Microsoft.KeyVault/locations/deletedVaults/purge/action' is required to purge a key vault.
# We'll check if the current user has this permission at the subscription scope.
# Note: This check is not exhaustive and might not cover all permission configurations (e.g., custom roles, management groups).

permission_check=$(az role assignment list --query "[?principalId=='$(az ad signed-in-user show --query id -o tsv)' && ends_with(roleDefinitionName, 'Key Vault Contributor') && scope=='/subscriptions/$(az account show --query id -o tsv)']" -o tsv)

if [ -z "$permission_check" ]; then
    echo "Warning: You may not have the required permissions to purge Key Vaults."
    echo "This script requires the 'Key Vault Contributor' role on the subscription."
    echo "To grant the required permission, run the following command:"
    echo "  az role assignment create --role 'Key Vault Contributor' --assignee '$(az ad signed-in-user show --query id -o tsv)' --scope '/subscriptions/$(az account show --query id -o tsv)'"

    read -p "Do you want to continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo "Fetching list of deleted Key Vaults..."

# Get deleted Key Vaults' names, locations, and purge protection status
deleted_vaults=$(az keyvault list-deleted --query "[].{name:name, location:properties.location, purgeProtection:properties.purgeProtectionEnabled}" -o json)

if [ -z "$deleted_vaults" ] || [ "$deleted_vaults" == "[]" ]; then
  echo "No deleted Key Vaults found to purge."
  exit 0
fi

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "jq is not installed. Please install jq to run this script."
    exit 1
fi

# Loop through the deleted vaults and purge them
echo "$deleted_vaults" | jq -c '.[]' | while read -r vault; do
  name=$(echo "$vault" | jq -r '.name')
  location=$(echo "$vault" | jq -r '.location')
  purge_protection=$(echo "$vault" | jq -r '.purgeProtection')

  if [ "$purge_protection" == "true" ]; then
    echo "Skipping Key Vault '$name' in location '$location' because purge protection is enabled."
    continue
  fi
  
  if [ -n "$name" ] && [ -n "$location" ]; then
    echo "Purging Key Vault '$name' in location '$location'..."
    az keyvault purge --name "$name" --location "$location"
    echo "Successfully purged Key Vault '$name'."
  else
    echo "Could not parse name or location for a deleted vault. Skipping."
  fi
done

echo "All deleted Key Vaults have been processed."
