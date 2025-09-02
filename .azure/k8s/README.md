# Privee Kubernetes Deployment

This directory contains Kubernetes manifests for deploying the Privee application to Azure Kubernetes Service (AKS).

## Files Overview

- `deployment.yml` - Main application deployment with 2 replicas (updated for CosmosDB PostgreSQL)
- `service.yml` - ClusterIP service for the application
- `headless-service.yml` - Headless service for Erlang clustering
- `ingress.yml` - Ingress configuration with SSL/TLS
- `secrets.yml` - Kubernetes secrets (placeholder values)
- `secret-provider-class.yml` - Azure Key Vault CSI driver configuration
- `deploy.sh` - Automated deployment script with CosmosDB endpoint detection
- `COSMOSDB-DEPLOYMENT.md` - Detailed documentation for CosmosDB PostgreSQL migration

## Prerequisites

1. Azure CLI installed and authenticated (`az login`)
2. kubectl installed and configured
3. **Infrastructure deployed first** (see below)

## Step 1: Deploy Infrastructure

Before deploying the Kubernetes resources, you need to deploy the Azure infrastructure including the Key Vault:

```bash
cd /home/mdacunzo/Projects/Privee/.azure
./deploy-infrastructure.sh
```

This will create:
- AKS cluster named `privee-aks` 
- Azure Container Registry (ACR)
- Key Vault for secrets management
- CosmosDB PostgreSQL cluster for distributed database capabilities
- PostgreSQL Flexible Server (for comparison/migration testing)
- Networking components (VNet, subnets, private DNS zones)
- Private endpoints for secure database connectivity

## Step 2: Build and Push Container Image

```bash
# Get ACR login server from deployment
ACR_LOGIN_SERVER=$(az deployment group show --resource-group privee-dev-rg --name main --query "properties.outputs.acrLoginServer.value" -o tsv)

# Build and push image
docker build -t $ACR_LOGIN_SERVER/privee:latest .
az acr login --name ${ACR_LOGIN_SERVER%%.azurecr.io}
docker push $ACR_LOGIN_SERVER/privee:latest
```

## Step 3: Deploy to Kubernetes

## Changes Made for privee-aks Cluster

### Recent Updates (Database Connection Fix)

1. **Fixed CosmosDB PostgreSQL Database Name**:
   - **Issue**: Application was trying to connect to database "citus" but CosmosDB cluster creates database "privee"
   - **Fix**: Updated `POSTGRES_DB` environment variable from `"citus"` to `"privee"` in deployment.yml
   - **Result**: Resolved `FATAL 3D000 (invalid_catalog_name) database "citus" does not exist` error

2. **Enhanced CosmosDB Integration**:
   - Deploy script now automatically detects CosmosDB coordinator endpoint
   - Uses actual endpoint: `c-priveecosmos.6nyivpmfw74dfe.postgres.cosmos.azure.com`
   - Proper SSL configuration with `ENABLE_DB_SSL: "true"`
   - Updated DATABASE_URL to use CosmosDB connection string format

### Previous Configuration Updates

1. **Fixed Ingress Configuration**:
   - Changed ingress name from `web` to `privee-ingress`
   - Updated service reference from `web` to `privee`
   - Updated secret name to match ingress name

2. **Updated Container Image**:
   - Changed from `privee.azurecr.io/privee` to `priveecr.azurecr.io/privee:latest`
   - Added explicit `latest` tag

3. **Added Namespace Declarations**:
   - Added explicit `namespace: default` to all resources for consistency

4. **DNS Policy Fix**:
   - Changed from `ClusterFirstWithHostNet` to `ClusterFirst` (recommended for most deployments)

5. **Updated Domain Configuration**:
   - Changed from `westeurope` to `northeurope` region
   - Updated Phoenix host configuration

6. **Added SecretProviderClass**:
   - Created configuration for Azure Key Vault CSI driver
   - Enables secure secret management through Azure Key Vault

## Deployment Instructions

### Prerequisites Check

Before deploying, ensure the Azure Key Vault provider for Secrets Store CSI Driver is enabled:

```bash
az aks show --resource-group privee-dev-rg --name privee-aks --query "addonProfiles.azureKeyvaultSecretsProvider.enabled"
```

If it returns `false` or `null`, you'll need to enable it (the main deploy script will do this automatically).

### Option 1: Full Deployment with Key Vault (Recommended)

Run the deployment script (it will automatically enable the CSI driver if needed and detect CosmosDB endpoint):

```bash
chmod +x deploy.sh
./deploy.sh
```

**What the script does:**
- Automatically detects CosmosDB PostgreSQL coordinator endpoint
- Configures proper database connection string with SSL
- Enables Secrets Store CSI Driver if not already enabled
- Applies all Kubernetes manifests with real values
- Waits for deployment rollout completion
- Provides access URL: `https://privee.northeurope.cloudapp.azure.com`

### Option 2: Quick Deployment without Key Vault

If you want to deploy quickly with static secrets first:

```bash
chmod +x deploy-no-keyvault.sh
./deploy-no-keyvault.sh
```

### Option 3: Manual Deployment

1. Get AKS credentials:
```bash
az aks get-credentials --resource-group privee-dev-rg --name privee-aks --overwrite-existing
```

2. Apply manifests:
```bash
kubectl apply -f secrets.yml
kubectl apply -f secret-provider-class.yml
kubectl apply -f service.yml
kubectl apply -f headless-service.yml
kubectl apply -f deployment.yml
kubectl apply -f ingress.yml
```

## Important Security Notes

1. **Update Secrets**: The `secrets.yml` file contains placeholder values. For production:
   - Generate new secrets: `mix phx.gen.secret`
   - Base64 encode them: `echo -n "your_secret" | base64 -w 0`
   - Update the secret values

2. **Use Azure Key Vault**: For production, configure the SecretProviderClass with your actual Key Vault and remove the static secrets.

3. **Container Registry**: Ensure the container registry URL matches your actual ACR name.

## Verification

After deployment, verify everything is working:

```bash
# Check pods (should show 2 running replicas)
kubectl get pods -l app=privee

# Check services
kubectl get svc

# Check ingress
kubectl get ingress

# View recent logs (should show successful migrations and no connection errors)
kubectl logs -l app=privee --tail=20

# Test database connectivity
kubectl exec -it deployment/privee -- mix ecto.ping

# Check environment variables (verify COSMOS_HOST and DATABASE_URL)
kubectl exec -it deployment/privee -- printenv | grep -E "(DATABASE_URL|COSMOS_HOST|POSTGRES_DB)"
```

**Expected healthy output:**
- Pods: `2/2 Running` with no restarts
- Logs: `Migrations already up` and `Running PriveeWeb.Endpoint`
- No `FATAL` database connection errors
- Application accessible at `https://privee.northeurope.cloudapp.azure.com`

## Troubleshooting

### Database Connection Issues

**Problem**: `FATAL 3D000 (invalid_catalog_name) database "citus" does not exist`
**Solution**: This has been fixed! The deployment now correctly uses database name "privee" instead of "citus".

**Problem**: CosmosDB connection timeout
**Solutions**:
1. Verify CosmosDB cluster is running: `az cosmosdb postgres cluster show --cluster-name priveecosmos --resource-group privee-dev-rg`
2. Check if coordinator endpoint is reachable from AKS cluster
3. Verify SSL configuration is enabled (`ENABLE_DB_SSL: "true"`)

### SecretProviderClass CRD Error

If you get an error like:
```
error: resource mapping not found for name: "azure-kv-privee" namespace: "default" from "./secret-provider-class.yml": no matches for kind "SecretProviderClass" in version "secrets-store.csi.x-k8s.io/v1"
ensure CRDs are installed first
```

**Solution 1**: Enable the Azure Key Vault provider add-on:
```bash
az aks enable-addons --resource-group privee-dev-rg --name privee-aks --addons azure-keyvault-secrets-provider
```

**Solution 2**: Use the alternative deployment script:
```bash
./deploy-no-keyvault.sh
```

### Other Common Issues

1. **Image Pull Errors**: Verify ACR authentication and image name
2. **Secret Issues**: Check base64 encoding and Key Vault configuration  
3. **Clustering Issues**: Verify headless service and DNS resolution
4. **Ingress Issues**: Check domain configuration and SSL certificates
5. **CosmosDB Issues**: Verify cluster is in "Ready" state and private endpoint connectivity

## Configuration Updates Needed

Before deploying, update these values in the files:

1. **Container Registry**: Update `priveecr.azurecr.io` with your actual ACR name
2. **Domain**: Update domain references with your actual domain  
3. **CosmosDB Connection**: The deploy script automatically detects the CosmosDB coordinator endpoint
4. **Key Vault**: Update Key Vault name in `secret-provider-class.yml`
5. **Secrets**: Generate and update all secret values

## Database Configuration

The application now uses **CosmosDB PostgreSQL** with the following configuration:

- **Database Name**: `privee` (configured in Bicep template)
- **Admin User**: `citus` (fixed for CosmosDB PostgreSQL)
- **Connection**: SSL enabled via private endpoint
- **Endpoint**: Automatically detected by deploy script
- **Format**: `ecto://citus:password@c-priveecosmos.uniqueid.postgres.cosmos.azure.com:5432/privee`

For detailed information about the CosmosDB migration, see `COSMOSDB-DEPLOYMENT.md`.