# Privee Kubernetes Deployment

This directory contains Kubernetes manifests for deploying the Privee application to Azure Kubernetes Service (AKS).

## Files Overview

- `deployment.yml` - Main application deployment with 3 replicas
- `service.yml` - ClusterIP service for the application
- `headless-service.yml` - Headless service for Erlang clustering
- `ingress.yml` - Ingress configuration with SSL/TLS
- `secrets.yml` - Kubernetes secrets (placeholder values)
- `secret-provider-class.yml` - Azure Key Vault CSI driver configuration
- `deploy.sh` - Automated deployment script

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
- Azure Container Registry
- Key Vault for secrets
- PostgreSQL database
- Networking components

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

Run the deployment script (it will automatically enable the CSI driver if needed):

```bash
chmod +x deploy.sh
./deploy.sh
```

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
# Check pods
kubectl get pods -l app=privee

# Check services
kubectl get svc

# Check ingress
kubectl get ingress

# View logs
kubectl logs -l app=privee
```

## Troubleshooting

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

## Configuration Updates Needed

Before deploying, update these values in the files:

1. **Container Registry**: Update `priveecr.azurecr.io` with your actual ACR name
2. **Domain**: Update domain references with your actual domain
3. **Database Host**: Update PostgreSQL host in `deployment.yml`
4. **Key Vault**: Update Key Vault name in `secret-provider-class.yml`
5. **Secrets**: Generate and update all secret values