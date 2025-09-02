# CosmosDB PostgreSQL Deployment Migration

This document explains the changes made to switch the Phoenix application from PostgreSQL Flexible Server to CosmosDB PostgreSQL.

## Changes Made

### 1. Kubernetes Deployment Configuration (`deployment.yml`)

The database configuration has been updated to use CosmosDB PostgreSQL:

```yaml
# Database configuration - Using CosmosDB PostgreSQL
- name: POSTGRES_USER
  valueFrom:
    secretKeyRef:
      name: postgres-secret
      key: POSTGRES_USER
- name: POSTGRES_PASSWORD
  valueFrom:
    secretKeyRef:
      name: postgres-secret
      key: POSTGRES_PASSWORD
- name: POSTGRES_DB
  value: "privee"  # CosmosDB PostgreSQL database name as configured in Bicep template
- name: POSTGRES_HOST
  value: privee-db.postgres.database.azure.com  # Kept for reference
- name: COSMOS_HOST
  value: "${COSMOS_COORDINATOR_ENDPOINT}"  # Dynamically resolved during deployment
- name: DATABASE_URL
  value: ecto://$(POSTGRES_USER):$(POSTGRES_PASSWORD)@$(COSMOS_HOST):5432/$(POSTGRES_DB)
```

**Key Changes:**
- Added `COSMOS_HOST` environment variable that gets populated during deployment
- Updated `DATABASE_URL` to use `$(COSMOS_HOST)` instead of `$(POSTGRES_HOST)`
- Kept same credentials (unified admin user/password)
- Added explicit port `:5432` for clarity

### 2. Deployment Script Updates (`deploy.sh`)

The deployment script now automatically fetches the CosmosDB coordinator endpoint:

```bash
# Get CosmosDB PostgreSQL coordinator endpoint
COSMOS_COORDINATOR_ENDPOINT=$(az cosmosdb postgres cluster show \
  --cluster-name "priveecosmoscluster" \
  --resource-group "$RESOURCE_GROUP" \
  --query "serverNames[0].fullyQualifiedDomainName" \
  -o tsv 2>/dev/null || true)
```

## Connection Details

### CosmosDB PostgreSQL Connection String Format:
```
ecto://pgadmin:password@c-priveecosmoscluster.uniqueID.privatelink.postgres.cosmos.azure.com:5432/privee
```

### Key Differences from PostgreSQL Flexible Server:
- **Host Format**: `c-<cluster-name>.<uniqueID>.privatelink.postgres.cosmos.azure.com`
- **Node Prefix**: `c-` indicates coordinator node
- **Private DNS**: Uses `privatelink.postgres.cosmos.azure.com` for private endpoints
- **Same Credentials**: Uses same `pgadmin` user and password as regular PostgreSQL

## Deployment Process

1. **Deploy Infrastructure**: Run the main Bicep deployment to create both databases
   ```bash
   cd .azure
   ./deploy.sh
   ```

2. **Deploy Application**: The K8s deployment script will automatically detect CosmosDB
   ```bash
   cd .azure/k8s
   ./deploy.sh
   ```

## Rollback Plan

To switch back to PostgreSQL Flexible Server:

1. Change the `DATABASE_URL` in `deployment.yml`:
   ```yaml
   - name: DATABASE_URL
     value: ecto://$(POSTGRES_USER):$(POSTGRES_PASSWORD)@$(POSTGRES_HOST)/$(POSTGRES_DB)
   ```

2. Redeploy the application:
   ```bash
   kubectl apply -f deployment.yml
   ```

## Verification

After deployment, verify the connection:

```bash
# Check pod logs
kubectl logs -l app=privee --tail=50

# Check database connection from within a pod
kubectl exec -it deployment/privee -- mix ecto.ping

# Verify environment variables
kubectl exec -it deployment/privee -- printenv | grep -E "(DATABASE_URL|COSMOS_HOST)"
```

## Benefits of the Switch

1. **Distributed Capabilities**: CosmosDB PostgreSQL provides Citus extension for horizontal scaling
2. **Cost Optimization**: Using single-node, burstable configuration
3. **Same Network**: Both databases in same private subnet/DNS zone
4. **Unified Credentials**: Same admin user/password for both databases
5. **Easy Migration**: Can switch between databases by changing environment variable

## Notes

- Both PostgreSQL and CosmosDB PostgreSQL run simultaneously in the same infrastructure
- The switch is accomplished purely through environment variable changes
- No Phoenix application code changes required
- SSL/TLS is enabled for both connections
- Private networking ensures secure communication
