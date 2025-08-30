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


Optional but recommended for CI/CD:
- GitHub Actions OIDC configured with `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, and `AZURE_CLIENT_ID` repository secrets.
### Deployment Order

#### 1. Deploy Key Vault First

The Key Vault must be deployed first as it's referenced by the main infrastructure:

./.azure/deploy-keyvault.sh --location northeurope --subscription YOUR_SUBSCRIPTION_ID
# Or to handle soft-deleted vaults automatically
./.azure/deploy-keyvault.sh --auto-recover
./deploy-keyvault.sh --location northeurope --subscription YOUR_SUBSCRIPTION_ID
```

This will output the Key Vault ID which you need to copy to `main.parameters.json`:

```json
{
  "keyVaultId": {
    "value": "/subscriptions/{subscription-id}/resourceGroups/privee-dev-kv-rg/providers/Microsoft.KeyVault/vaults/privee-kv"
./.azure/deploy.sh
}

Note: The scripts do not modify `main.parameters.json` automatically. Ensure `keyVaultId` is set before running the main deployment. The Key Vault script prints the exact value to use.

### Run from GitHub Actions (on-demand)

There is a manual workflow that runs both steps in order: Key Vault (with auto-recover) then main infrastructure.

Workflow: `.github/workflows/azure-provision.yml`

- Trigger: manual only (workflow_dispatch). No automatic triggers.
- Steps executed:
  1) `./.azure/deploy-keyvault.sh --auto-recover`
  2) `./.azure/deploy.sh`

Before running it, make sure `keyVaultId` is already set in `./.azure/main.parameters.json`.
```

For detailed Key Vault deployment instructions, see [KEYVAULT_DEPLOYMENT.md](./KEYVAULT_DEPLOYMENT.md).

The Managed Identity for GitHub Actions (UAMI + federated credential) and its required role assignments (ACR + AKS RBAC) are provisioned as part of the main deployment via the module `modules/gha-oidc-identity.bicep` invoked by `./.azure/deploy.sh`. A separate identity-only script is not required for normal operations.

Legacy helper:
- `./.azure/scripts/deploy-mi.sh` can deploy only the identity and related role assignments. This is now redundant and should be used only for ad‑hoc identity repairs or troubleshooting.
./deploy.sh
```
./.azure/scripts/purge-kv.sh
## Key Vault Management

### Recovering a Deleted Key Vault
./.azure/scripts/migrate-secrets-to-kv.sh
If a Key Vault is accidentally deleted, it can be recovered within the soft-delete retention period, provided it has not been purged.

To recover a deleted Key Vault, use the following Azure CLI command:
./.azure/scripts/delete-resource-groups.sh
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
 
## Why there are two Public IPs in the AKS node resource group

With AKS using the Standard Load Balancer (default), Azure typically provisions two Public IPs in the AKS node resource group (MC_...):

- Outbound Public IP: managed by AKS for egress from cluster nodes (image pulls, OS/package updates, calls to Azure services). This IP belongs to the managed outbound load balancer and should not have a DNS label.
- Ingress Public IP: created by the Web App Routing add-on (Service type LoadBalancer) for inbound traffic to your apps. This IP is the one that receives the DNS label (configured via `modules/ingress-dnslabel.bicep` and the `ingressDnsLabel` parameter in `main.bicep`).

This is expected and recommended. Only the ingress IP gets your DNS name (e.g., `privee`). The outbound IP remains unlabeled and is used exclusively for egress.

If you must have a single, controlled egress IP, you can replace the AKS-managed outbound with a NAT Gateway:

1) Create a Standard Public IP and a NAT Gateway
2) Associate the NAT Gateway to the AKS subnet
3) Set AKS `outboundType` to `userDefinedRouting`

Important: using `userDefinedRouting` without providing NAT/UDR breaks the default AKS-managed outbound load balancer, and scripts that expect the standard load balancer may fail until ingress is provisioned. Ensure NAT is in place to restore egress.