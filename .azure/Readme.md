# Azure Infrastructure and Operations

This document outlines the procedures for deploying and managing the Azure infrastructure for this project.

## Deployment

The infrastructure is now split into two main components:
1. **Key Vault** - Deployed independently for security isolation
2. **Main Infrastructure** - Includes AKS, networking, PostgreSQL, and other resources

### Prerequisites

- Azure CLI installed and authenticated (`az login`).
- Permissions to create resource groups and deploy resources at the subscription level.

### Known Deployment Warnings

During deployment, you may see warnings like:

```
[CONCAT('/subscriptions/.../registries/priveeregistry/providers/', concat('Microsoft.Authorization/roleAssignments/', guid(...)))] (Unsupported) Changes to the resource declared at 'properties.template.resources[2].properties.template.resources[0]' on line X and column Y cannot be analyzed because its resource ID or API version cannot be calculated until the deployment is under way.
```

**These warnings are safe to ignore.** They occur because ARM's what-if analysis cannot predict the exact resource IDs for role assignments that use dynamic GUID generation. The actual deployment will work correctly.

### Deployment Order

#### 1. Deploy Key Vault First

The Key Vault must be deployed first as it's referenced by the main infrastructure:

```bash
./deploy-keyvault.sh --location northeurope --subscription YOUR_SUBSCRIPTION_ID
```

This will output the Key Vault ID which you need to copy to `main.parameters.json`:

```json
{
  "keyVaultId": {
    "value": "/subscriptions/{subscription-id}/resourceGroups/privee-dev-kv-rg/providers/Microsoft.KeyVault/vaults/privee-kv"
  }
}
```

For detailed Key Vault deployment instructions, see [KEYVAULT_DEPLOYMENT.md](./KEYVAULT_DEPLOYMENT.md).

#### 2. Deploy Main Infrastructure

After updating the Key Vault ID in parameters, deploy the main infrastructure:

```bash
./deploy.sh
```

## Key Vault Management

### Recovering a Deleted Key Vault

If a Key Vault is accidentally deleted, it can be recovered within the soft-delete retention period, provided it has not been purged.

To recover a deleted Key Vault, use the following Azure CLI command:

```sh
az keyvault recover --name <namePrefix>-kv --location <location>
```

- Replace `<namePrefix>` with the prefix used for your resources (e.g., `privee`).
- Replace `<location>` with the Azure region where the Key Vault was deployed.

The `namePrefix` and `location` can be found in the `main-subscription.bicep` file or your deployment parameters.

### Purging a Deleted Key Vault

If you need to permanently delete a Key Vault that is in a soft-deleted state, you can use the `purge-kv.sh` script. This is necessary if you want to recreate a Key Vault with the same name.

**Warning:** This action is irreversible.

```bash
./scripts/purge-kv.sh
```

The script will list all soft-deleted Key Vaults in the subscription and prompt for confirmation before purging them.

## Secrets Management

Application secrets are managed in Azure Key Vault. The `migrate-secrets-to-kv.sh` script helps in setting up initial secrets.

```bash
./scripts/migrate-secrets-to-kv.sh
```

This script will prompt for secret values and store them securely in the designated Key Vault.

## GitHub Actions Integration

The `scripts/deploy-mi.sh` script is used to set up a Managed Identity for GitHub Actions. This allows workflows to securely authenticate with Azure without needing to store credentials as long-lived secrets in GitHub.

To run it:
```bash
./scripts/deploy-mi.sh
```

## Cleanup

To delete all the resource groups and resources created by the deployment, you can use the `delete-resource-groups.sh` script.

**Warning:** This will permanently delete all resources defined in the script.

```bash
./scripts/delete-resource-groups.sh
```