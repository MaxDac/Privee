# Azure Infrastructure and Operations

This document outlines the procedures for deploying and managing the Azure infrastructure for this project.

## Recent Updates

### Database Connection Fix (September 2025)
- **Fixed CosmosDB PostgreSQL database connection issue**: The application was trying to connect to database "citus" but the CosmosDB cluster creates database "privee"
- **Updated Kubernetes deployment**: Changed `POSTGRES_DB` environment variable from `"citus"` to `"privee"`
- **Enhanced deployment script**: Now automatically detects CosmosDB coordinator endpoint
- **Improved documentation**: Added comprehensive troubleshooting and verification steps

### Infrastructure Components
- **CosmosDB PostgreSQL**: Distributed database with private endpoint connectivity
- **PostgreSQL Flexible Server**: For comparison/migration testing
- **Azure Kubernetes Service (AKS)**: Container orchestration with 2 replicas
- **Azure Container Registry (ACR)**: Private container registry
- **Azure Key Vault**: Secure secrets management with CSI driver integration
- **Networking**: VNet with private subnets and DNS zones

## Initial Deployment

The infrastructure is now split into two main components:
1. **Key Vault** - Deployed independently for security isolation
2. **Main Infrastructure** - Includes AKS, networking, CosmosDB PostgreSQL, and other resources

### Prerequisites

- Azure CLI installed and authenticated (`az login`)
- Docker installed (for application image building)
- kubectl installed and configured
- GitHub CLI (gh) installed and authenticated (for secrets management)
- Permissions to create resource groups and deploy resources at the subscription level

### Known Deployment Warnings

During deployment, you may see warnings like:

```
[CONCAT('/subscriptions/.../registries/priveeregistry/providers/', concat('Microsoft.Authorization/roleAssignments/', guid(...)))] (Unsupported) Changes to the resource declared at 'properties.template.resources[2].properties.template.resources[0]' on line X and column Y cannot be analyzed because its resource ID or API version cannot be calculated until the deployment is under way.
```

**These warnings are safe to ignore.** They occur because ARM's what-if analysis cannot predict the exact resource IDs for role assignments that use dynamic GUID generation. The actual deployment will work correctly.


Optional but recommended for CI/CD:
- GitHub Actions OIDC configured with `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, and `AZURE_CLIENT_ID` repository secrets.
### Initial Deployment Order

#### 1. Deploy Key Vault First

The Key Vault must be deployed first as it's referenced by the main infrastructure:

```bash
./.azure/deploy-keyvault.sh --location northeurope --subscription YOUR_SUBSCRIPTION_ID
# Or to handle soft-deleted vaults automatically
./.azure/deploy-keyvault.sh --auto-recover
```

This will output the Key Vault ID which you need to copy to `main.parameters.json`:

```json
{
  "keyVaultId": {
    "value": "/subscriptions/{subscription-id}/resourceGroups/privee-dev-kv-rg/providers/Microsoft.KeyVault/vaults/privee-kv"
  }
}
```

Note: The scripts do not modify `main.parameters.json` automatically. Ensure `keyVaultId` is set before running the main deployment.

#### 2. Deploy Main Infrastructure

After updating the `keyVaultId` parameter, deploy the main infrastructure:

```bash
./.azure/deploy.sh
```

This creates:
- AKS cluster with Web App Routing
- Azure Container Registry (ACR)
- CosmosDB PostgreSQL cluster
- PostgreSQL Flexible Server
- Networking components (VNet, subnets, private DNS zones)
- Private endpoints for secure database connectivity
- Managed Identity for GitHub Actions

#### 3. Deploy Kubernetes Resources

Deploy the application to the AKS cluster:

```bash
cd .azure/k8s
./deploy.sh
```

This automatically:
- Detects CosmosDB coordinator endpoint
- Configures SSL database connections
- Deploys application with 2 replicas
- Sets up ingress with HTTPS
- Integrates with Azure Key Vault for secrets

#### 4. Set Up Secrets and GitHub Integration

Configure application secrets and GitHub Actions:

```bash
# Set secrets in Key Vault
./.azure/scripts/set-secrets-to-dev-kv.sh

# Configure GitHub repository secrets for CI/CD
./.azure/scripts/push-info-to-gh-secrets.sh
```

#### 5. Build and Deploy Application Image

Build and push the application container image:

```bash
# Build and push to ACR (requires Docker)
./.azure/scripts/local-deploy.sh
```

## Complete Cluster Redeployment Guide

If you need to completely redeploy the cluster from scratch, follow these steps in order:

### Step 1: Deploy Key Vault with Auto-Recovery
```bash
cd .azure
./deploy-keyvault.sh --auto-recover
```
**What it does:** Automatically recovers any soft-deleted Key Vault or creates a new one if none exists.

### Step 2: Deploy Main Infrastructure
```bash
./deploy.sh
```
**What it does:** Creates all Azure resources (AKS, ACR, CosmosDB, networking, managed identity, etc.).

### Step 3: Deploy Kubernetes Resources
```bash
cd k8s
./deploy.sh
```
**What it does:** 
- Automatically detects CosmosDB endpoint
- Deploys application pods with correct database configuration
- Sets up ingress with SSL/TLS
- Integrates with Azure Key Vault for secrets

### Step 4: Configure Secrets
```bash
cd ..
# Set up GitHub repository secrets for CI/CD
./scripts/push-info-to-gh-secrets.sh

# Configure application secrets in Key Vault  
./scripts/set-secrets-to-dev-kv.sh
```
**What it does:** 
- Exports Azure credentials to GitHub repository secrets
- Creates application secrets (database password, secret key base) in Key Vault

### Step 5: Build and Push Application Image
```bash
# Build and push container image to ACR (requires Docker)
./scripts/local-deploy.sh
```
**What it does:**
- Builds Phoenix/Elixir application container
- Pushes to Azure Container Registry
- Updates Kubernetes deployment with new image

### Step 6: Final Kubernetes Deployment
```bash
cd k8s
./deploy.sh
```
**What it does:** Ensures the application is running with the latest configuration and image.

### Verification

After redeployment, verify everything is working:

```bash
# Check pod status
kubectl get pods -l app=privee

# Check application logs (should show successful migrations)
kubectl logs -l app=privee --tail=20

# Test database connectivity
kubectl exec -it deployment/privee -- mix ecto.ping

# Access the application
echo "Application available at: https://privee.northeurope.cloudapp.azure.com"
```

**Expected Results:**
- 2 running pods with no restarts
- Logs showing "Migrations already up" and "Running PriveeWeb.Endpoint"
- No database connection errors
- Application accessible via HTTPS

## GitHub Actions Deployment

### Manual Workflow

There is a manual workflow that runs both steps in order: Key Vault (with auto-recover) then main infrastructure.

**Workflow:** `.github/workflows/azure-provision.yml`

- **Trigger:** Manual only (workflow_dispatch). No automatic triggers.
- **Prerequisites:** Ensure `keyVaultId` is set in `./.azure/main.parameters.json` before running.
- **Steps executed:**
  1. `./.azure/deploy-keyvault.sh --auto-recover`
  2. `./.azure/deploy.sh`

### CI/CD Integration

The deployment includes a Managed Identity for GitHub Actions with federated credentials. This enables secure authentication without storing long-lived secrets.

**Required GitHub Repository Secrets:**
- `AZURE_TENANT_ID` - Azure AD tenant ID
- `AZURE_SUBSCRIPTION_ID` - Azure subscription ID  
- `AZURE_CLIENT_ID` - Managed identity client ID

These are automatically configured by running:
```bash
./.azure/scripts/push-info-to-gh-secrets.sh
```
```
./.azure/scripts/purge-kv.sh
## Troubleshooting

### Database Connection Issues

**Problem:** `FATAL 3D000 (invalid_catalog_name) database "citus" does not exist`
**Status:** ✅ **FIXED** - The deployment now correctly uses database name "privee" instead of "citus"

**Problem:** CosmosDB connection timeout or SSL errors
**Solutions:**
1. Verify CosmosDB cluster is running: 
   ```bash
   az cosmosdb postgres cluster show --cluster-name priveecosmos --resource-group privee-dev-rg
   ```
2. Check SSL configuration is enabled (`ENABLE_DB_SSL: "true"`)
3. Verify private endpoint connectivity from AKS cluster

### Application Deployment Issues

**Problem:** Pods stuck in CrashLoopBackOff
**Solutions:**
1. Check application logs: `kubectl logs -l app=privee --tail=50`
2. Verify secrets are accessible: `kubectl describe pod -l app=privee`
3. Test database connectivity: `kubectl exec -it deployment/privee -- mix ecto.ping`

**Problem:** Image pull errors
**Solutions:**
1. Verify ACR authentication: `az acr login --name priveeregistry`
2. Check image exists: `az acr repository list --name priveeregistry`
3. Ensure AKS has pull permissions on ACR

### Infrastructure Issues

**Problem:** Key Vault deployment fails
**Solution:** Use auto-recovery for soft-deleted vaults:
```bash
./deploy-keyvault.sh --auto-recover
```

**Problem:** Role assignment warnings during deployment
**Status:** ✅ **Safe to ignore** - ARM cannot analyze dynamic role assignment GUIDs during what-if operations

### Useful Commands

```bash
# Check overall cluster health
kubectl get nodes
kubectl get pods --all-namespaces

# Check application status
kubectl get pods -l app=privee
kubectl logs -l app=privee --tail=20

# Check database connectivity
kubectl exec -it deployment/privee -- mix ecto.ping

# Check CosmosDB cluster status
az cosmosdb postgres cluster show --cluster-name priveecosmos --resource-group privee-dev-rg

# Check ACR images
az acr repository list --name priveeregistry
```
./.azure/scripts/migrate-secrets-to-kv.sh
## Key Vault Management

### Recovering a Deleted Key Vault

If a Key Vault is accidentally deleted, it can be recovered within the soft-delete retention period (90 days by default), provided it has not been purged.

**Automatic Recovery:**
```bash
./deploy-keyvault.sh --auto-recover
```

**Manual Recovery:**
```bash
az keyvault recover --name privee-kv --location northeurope
```

### Purging a Deleted Key Vault

If you need to permanently delete a Key Vault that is in a soft-deleted state, you can use the `purge-kv.sh` script. This is necessary if you want to recreate a Key Vault with the same name.

**⚠️ Warning:** This action is irreversible and will permanently delete all secrets.

```bash
./scripts/purge-kv.sh
```

The script will list all soft-deleted Key Vaults in the subscription and prompt for confirmation before purging them.

## Secrets Management

Application secrets are managed in Azure Key Vault and automatically integrated into Kubernetes via the CSI driver.

### Setting Up Initial Secrets

```bash
./scripts/set-secrets-to-dev-kv.sh
```

This script creates the following secrets in Key Vault:
- `COSMOS-USER`: CosmosDB PostgreSQL admin username (citus)
- `COSMOS-PASSWORD`: CosmosDB PostgreSQL admin password
- `COSMOS-DB`: CosmosDB PostgreSQL database name (privee)  
- `privee-secret-key-base`: Phoenix application secret key

### Secret Integration

The Kubernetes deployment automatically mounts secrets from Key Vault using:
- **Azure Key Vault CSI Driver**: Secure secret mounting
- **SecretProviderClass**: Maps Key Vault secrets to Kubernetes environment variables
- **Managed Identity**: Secure authentication without stored credentials

## Container Image Management

### Building and Pushing Images

The application uses a containerized deployment model with images stored in Azure Container Registry.

**Local Development:**
```bash
./scripts/local-deploy.sh
```

**What it does:**
- Builds Phoenix/Elixir application container with production configuration
- Tags with git SHA and 'latest'
- Pushes to Azure Container Registry (priveeregistry.azurecr.io)
- Updates Kubernetes deployment with new image
- Waits for rollout completion

### Image Tagging Strategy

- **Latest:** `priveeregistry.azurecr.io/privee:latest`
- **Git SHA:** `priveeregistry.azurecr.io/privee:{git-sha}`
- **Build metadata:** Includes build date and VCS reference

## Legacy and Maintenance Scripts

### Identity Management
- `./scripts/deploy-mi.sh` - Deploy only the managed identity and related role assignments (now redundant, handled by main deployment)

### Cleanup and Maintenance
```bash
# Delete all resource groups (⚠️ DESTRUCTIVE)
./scripts/delete-resource-groups.sh

# Purge soft-deleted Key Vault (⚠️ IRREVERSIBLE)
./scripts/purge-kv.sh
```

**⚠️ Warning:** These cleanup scripts will permanently delete resources. Use with extreme caution.

## Advanced Configuration

### DNS and Ingress

The deployment includes:
- **Automatic DNS setup**: Creates managed DNS zone with proper NS delegation
- **SSL/TLS certificates**: Integrated with Let's Encrypt via cert-manager
- **Ingress routing**: Azure Application Gateway with Web App Routing
- **Domain**: `privee.northeurope.cloudapp.azure.com`

### Networking Architecture

```
Internet → Application Gateway (HTTPS) → AKS Ingress → Application Pods
                                              ↓
Private Endpoints → CosmosDB PostgreSQL (SSL)
                 → Azure Key Vault (secrets)
```

**Security Features:**
- Private endpoints for database connectivity
- Network policies for pod-to-pod communication
- Azure Key Vault integration with CSI driver
- SSL/TLS termination at ingress
- Managed identities for secure authentication
 
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