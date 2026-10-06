# Infrastructure and Deployment

This directory contains infrastructure configuration and deployment scripts for the Privee application.

## Files

- `deploy-aks.sh` - Script to deploy the application to Azure AKS
- `check-aks.sh` - Script to check the status of AKS deployment
- `deploy-fly.sh` - Script to deploy the application to Fly.io

## Usage

### Azure AKS Deployment

1. Ensure you have `kubectl` configured to connect to your AKS cluster
2. Ensure you have Docker access to your Azure Container Registry
3. Run the deployment script:

   ```bash
   ./infra/deploy-aks.sh
   ```

### Check AKS Status

```bash
./infra/check-aks.sh
```

### Fly.io Deployment  

```bash
./infra/deploy-fly.sh
```

## Prerequisites

- Docker
- kubectl (for AKS)
- flyctl (for Fly.io)
- Appropriate authentication configured for your cloud platform

## Private DNS Zone

```bash
az network private-dns record-set list --resource-group <ResourceGroupName> --zone-name <PrivateDNSZoneName> --query "[].fqdn"
```

This gets all the qualified DNSs. The DB entry should use the Private DNS Zone name as a suffix, i.e. `privee-db.private.postgres.database.azure.com` where the Private DNS Zone name is `privee-db.private.postgres.database.azure.com`

