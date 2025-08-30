# Standalone Key Vault Deployment

This directory contains a standalone Key Vault deployment template that can be deployed independently of the main infrastructure.

## Overview

The Key Vault has been extracted from the main deployment templates to allow for:
- Independent deployment and management of Key Vault resources
- Better separation of concerns between security infrastructure and compute infrastructure
- Ability to deploy Key Vault once and reference it from multiple deployments

## Files

- `modules/keyvault-standalone.bicep` - Main Key Vault deployment template (subscription scope)
- `keyvault-standalone.parameters.json` - Parameters file for Key Vault deployment
- `deploy-keyvault.sh` - Deployment script for Key Vault

## Deployment Order

### 1. Deploy Key Vault (First)

Deploy the standalone Key Vault first:

```bash
# Using the deployment script (interactive - will prompt if soft-deleted vault exists)
./deploy-keyvault.sh --location northeurope --subscription YOUR_SUBSCRIPTION_ID

# Auto-recover existing soft-deleted Key Vault (recommended for preserving secrets)
./deploy-keyvault.sh --location northeurope --subscription YOUR_SUBSCRIPTION_ID --auto-recover

# Or using Azure CLI directly
az deployment sub create \
  --location northeurope \
  --template-file modules/keyvault-standalone.bicep \
  --parameters keyvault-standalone.parameters.json \
  --name keyvault-deployment
```

### 2. Update Main Parameters

After Key Vault deployment, update the `keyVaultId` parameter in `main.parameters.json` with the output from step 1:

```json
{
  "keyVaultId": {
    "value": "/subscriptions/{subscription-id}/resourceGroups/privee-dev-kv-rg/providers/Microsoft.KeyVault/vaults/privee-kv"
  }
}
```

### 3. Deploy Main Infrastructure

Deploy the main infrastructure referencing the existing Key Vault:

```bash
# Deploy main infrastructure
az deployment sub create \
  --location northeurope \
  --template-file main-subscription.bicep \
  --parameters main.parameters.json \
  --name main-deployment
```

## Configuration

### Key Vault Parameters

Update `keyvault-standalone.parameters.json` with your desired values:

- `namePrefix`: Prefix for resource names (default: "privee")
- `location`: Azure region (default: "East US 2")
- `environment`: Environment name (default: "dev")
- `tags`: Additional tags for resources

### Resource Naming

The Key Vault resources will be created with these names:
- Resource Group: `{namePrefix}-{environment}-kv-rg`
- Key Vault: `{namePrefix}-kv`

## Security Notes

- Key Vault has RBAC authorization enabled
- Soft delete and purge protection are enabled
- Network access is configured to allow Azure services by default

## Outputs

The deployment provides these outputs:
- `keyVaultId`: Full resource ID of the Key Vault
- `keyVaultName`: Name of the Key Vault
- `keyVaultResourceGroupName`: Name of the Key Vault resource group

Use the `keyVaultId` output in your main infrastructure deployment parameters.

## Handling Soft-Deleted Key Vaults

Azure Key Vault has soft-delete protection enabled by default. If you previously had a Key Vault with the same name that was deleted, you may encounter a conflict error during deployment.

### Error Symptoms
```
ConflictError: A vault with the same name already exists in deleted state. You need to either recover or purge existing key vault.
```

### Solutions

The `deploy-keyvault.sh` script automatically detects this situation and provides options:

1. **Recover the existing Key Vault (Recommended)**
   - Restores the soft-deleted Key Vault with existing secrets intact
   - Use `--auto-recover` flag for automation: `./deploy-keyvault.sh --auto-recover`
   - No data loss

2. **Manual purge using existing script**
   - Use the existing purge script: `./scripts/purge-kv.sh`
   - ⚠️ **WARNING**: All secrets will be permanently lost

3. **Manual handling via Azure CLI**
   ```bash
   # List soft-deleted Key Vaults
   az keyvault list-deleted
   
   # Recover a specific Key Vault
   az keyvault recover --name privee-kv --location northeurope
   
   # Or purge a specific Key Vault (if not purge-protected)
   az keyvault purge --name privee-kv --location northeurope
   ```
