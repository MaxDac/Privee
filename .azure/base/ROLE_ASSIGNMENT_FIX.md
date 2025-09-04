# Fixing Azure Role Assignment Deployment Issues

## Problem
When deploying the admin identity infrastructure, you might encounter the following error:

```
{"status":"Failed","error":{"code":"DeploymentFailed","message":"At least one resource deployment operation failed.","details":[{"code":"RoleAssignmentUpdateNotPermitted","message":"Tenant ID, application ID, principal ID, and scope are not allowed to be updated."}]}}
```

This happens because Azure role assignments have immutable properties and cannot be updated once created.

## Solution Options

### Option 1: Use the Cleanup Script (Recommended)

Run the cleanup script to remove existing role assignments before redeployment:

```bash
# Navigate to the base directory
cd .azure/base

# Clean up existing role assignments
./cleanup-role-assignments.sh

# Deploy with automatic cleanup
./deploy.sh --cleanup-roles
```

### Option 2: Manual Cleanup via Azure CLI

1. Find the principal ID of your managed identity:
   ```bash
   az identity show --resource-group "privee-identity-rg" --name "privee-gha-admin-dev" --query principalId -o tsv
   ```

2. List existing role assignments:
   ```bash
   az role assignment list --assignee <PRINCIPAL_ID> --scope "/subscriptions/<SUBSCRIPTION_ID>"
   ```

3. Delete the problematic role assignments:
   ```bash
   az role assignment delete --ids <ROLE_ASSIGNMENT_ID>
   ```

### Option 3: Delete and Recreate the Identity Resource Group

If the above options don't work, you can delete the entire identity resource group:

```bash
# Using the provided cleanup script
.azure/scripts/delete-resource-groups.sh --delete-admin-identity

# Or manually
az group delete --name "privee-identity-rg" --yes --no-wait
```

Then redeploy:

```bash
cd .azure/base
./deploy.sh
```

## Prevention

To prevent this issue in the future:

1. **Use the `--cleanup-roles` option** when redeploying:
   ```bash
   ./deploy.sh --cleanup-roles
   ```

2. **Avoid manual changes** to role assignments that were created by the deployment templates.

3. **Use different deployment names** if you need to test multiple deployments.

## Files Modified

- `admin-identity.bicep`: Updated to use more unique GUIDs for role assignments and proper dependency management
- `deploy.sh`: Added `--cleanup-roles` option for automatic cleanup before deployment
- `cleanup-role-assignments.sh`: New script for cleaning up existing role assignments
- `delete-resource-groups.sh`: Added conditional deletion of `privee-identity-rg`

## Deployment Script Options

The deployment script now supports:

```bash
./deploy.sh [OPTIONS]

Options:
  -s, --subscription-id ID    Azure subscription ID
  -l, --location LOCATION     Azure region (default: West Europe)
  -p, --parameters FILE       Parameters file path
  -n, --deployment-name NAME  Custom deployment name
  -c, --cleanup-roles         Clean up existing role assignments before deployment
  -h, --help                  Show help message
```
