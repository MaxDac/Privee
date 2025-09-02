# CosmosDB PostgreSQL Operations Guide

This guide covers how to interact with the CosmosDB PostgreSQL cluster deployed using the infrastructure in this project.

## Overview

The CosmosDB PostgreSQL cluster is deployed using the `modules/cosmosdb-postgresql.bicep` template and provides:

- **Database**: `privee` (as configured in the Bicep template)
- **Admin User**: `citus` (fixed value for CosmosDB PostgreSQL)
- **PostgreSQL Version**: 16
- **Configuration**: Single-node, cost-optimized setup with private endpoint access
- **High Availability**: Disabled for cost optimization
- **Extensions**: Support for extensions like `citext` (must be enabled manually)

## Azure CLI Operations

### Prerequisites

Ensure you have:
- Azure CLI installed and authenticated (`az login`)
- Access to the resource group containing your CosmosDB PostgreSQL cluster
- Appropriate permissions to query Azure resources

### 1. List CosmosDB PostgreSQL Clusters

```bash
# List all clusters in a resource group
az cosmosdb postgres cluster list --resource-group <your-resource-group-name>

# List all clusters in the subscription
az cosmosdb postgres cluster list
```

### 2. Show Cluster Details

```bash
az cosmosdb postgres cluster show \
  --cluster-name <your-cluster-name> \
  --resource-group <your-resource-group-name>
```

This command returns detailed information including:
- Server names and endpoints
- Configuration details
- Status and provisioning state
- Connection information

### 3. Get Connection String Information

```bash
# Show connection string format
az postgres flexible-server show-connection-string \
  --server-name <your-cluster-name> \
  --database-name privee \
  --admin-user citus \
  --admin-password <your-password>
```

### 4. Manage Cluster Operations

```bash
# Start the cluster (if stopped)
az cosmosdb postgres cluster start \
  --cluster-name <your-cluster-name> \
  --resource-group <your-resource-group-name>

# Stop the cluster (to save costs)
az cosmosdb postgres cluster stop \
  --cluster-name <your-cluster-name> \
  --resource-group <your-resource-group-name>

# Restart the cluster
az cosmosdb postgres cluster restart \
  --cluster-name <your-cluster-name> \
  --resource-group <your-resource-group-name>
```

### 5. Manage Firewall Rules (if needed)

```bash
# Add your IP to firewall rules (for development access)
az cosmosdb postgres firewall-rule create \
  --cluster-name <your-cluster-name> \
  --resource-group <your-resource-group-name> \
  --rule-name "AllowMyIP" \
  --start-ip-address <your-ip> \
  --end-ip-address <your-ip>

# List firewall rules
az cosmosdb postgres firewall-rule list \
  --cluster-name <your-cluster-name> \
  --resource-group <your-resource-group-name>

# Delete a firewall rule
az cosmosdb postgres firewall-rule delete \
  --cluster-name <your-cluster-name> \
  --resource-group <your-resource-group-name> \
  --rule-name "AllowMyIP"
```

## PostgreSQL Client Connection

### Connection Parameters

Based on the Bicep template configuration:

- **Host**: The coordinator endpoint (use the FQDN from cluster details)
- **Port**: `5432` (default PostgreSQL port)
- **Database**: `privee`
- **Username**: `citus`
- **Password**: The administrator password set during deployment
- **SSL Mode**: `require` (mandatory for CosmosDB PostgreSQL)

### Connection Methods

#### 1. Using psql Command Line

```bash
# Connect using connection string format
psql "host=c-priveecosmos.5bwsp5etlxdldh.postgres.cosmos.azure.com port=5432 dbname=privee user=citus password=<your-password> sslmode=require"

# Connect using individual parameters
psql -h c-priveecosmos.5bwsp5etlxdldh.postgres.cosmos.azure.com -p 5432 -U citus -d privee

# Alternative with SSL requirement
psql "postgresql://citus:<your-password>@c-priveecosmos.5bwsp5etlxdldh.postgres.cosmos.azure.com:5432/privee?sslmode=require"

# Connect to default privee database (the one created by our Bicep template)
psql "host=c-priveecosmos.5bwsp5etlxdldh.postgres.cosmos.azure.com port=5432 dbname=privee user=citus sslmode=require"
```

**Connection Requirements:**
- SSL Mode: `require` (mandatory)
- You will be prompted for the administrator password
- Ensure your IP is in the firewall rules (current rule: 109.78.156.138)

**Troubleshooting Connection Issues:**

If you encounter "remaining connection slots are reserved" error:
1. The burstable tier has limited connections (20 total)
2. Some connections may be reserved for system use
3. Try connecting during off-peak times
4. Consider stopping and starting the cluster to clear connections:
   ```bash
   az cosmosdb postgres cluster stop --cluster-name priveecosmos --resource-group privee-dev-rg
   # Wait 30 seconds
   az cosmosdb postgres cluster start --cluster-name priveecosmos --resource-group privee-dev-rg
   ```

#### 2. Using Environment Variables

```bash
export PGHOST=<coordinator-endpoint>
export PGPORT=5432
export PGDATABASE=privee
export PGUSER=citus
export PGPASSWORD=<your-password>
export PGSSLMODE=require

psql
```

#### 3. Connection from Applications

**Node.js (using pg library):**
```javascript
const { Client } = require('pg');

const client = new Client({
  host: '<coordinator-endpoint>',
  port: 5432,
  database: 'privee',
  user: 'citus',
  password: '<your-password>',
  ssl: { rejectUnauthorized: false }
});
```

**Python (using psycopg2):**
```python
import psycopg2

conn = psycopg2.connect(
    host="<coordinator-endpoint>",
    port=5432,
    database="privee",
    user="citus",
    password="<your-password>",
    sslmode="require"
)
```

**Elixir (using Ecto):**
```elixir
config :your_app, YourApp.Repo,
  username: "citus",
  password: "<your-password>",
  hostname: "<coordinator-endpoint>",
  database: "privee",
  port: 5432,
  ssl: true,
  ssl_opts: [verify: :verify_none]
```

## Database Setup and Extensions

### Enable Required Extensions

After connecting to the database, enable commonly needed extensions:

```sql
-- Enable case-insensitive text extension
CREATE EXTENSION IF NOT EXISTS citext;

-- Enable UUID generation functions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Enable advanced indexing (if needed)
CREATE EXTENSION IF NOT EXISTS btree_gin;
CREATE EXTENSION IF NOT EXISTS btree_gist;

-- Enable Citus distributed tables (if scaling horizontally)
CREATE EXTENSION IF NOT EXISTS citus;
```

### Basic Database Operations

```sql
-- List all databases
\l

-- List all tables in current database
\dt

-- List all extensions
\dx

-- Show database connection info
\conninfo

-- Show current user and database
SELECT current_user, current_database();

-- Check Citus version (if applicable)
SELECT citus_version();
```

## Monitoring and Maintenance

### Check Cluster Status

```bash
# Get cluster status and configuration
az cosmosdb postgres cluster show \
  --cluster-name <your-cluster-name> \
  --resource-group <your-resource-group-name> \
  --query "{name:name, state:state, postgresqlVersion:postgresqlVersion, coordinatorVCores:coordinatorVCores}"
```

### Monitor Connections

```sql
-- Show active connections
SELECT pid, usename, application_name, client_addr, state, query_start 
FROM pg_stat_activity 
WHERE state = 'active';

-- Show database statistics
SELECT datname, numbackends, xact_commit, xact_rollback, blks_read, blks_hit 
FROM pg_stat_database 
WHERE datname = 'privee';
```

## Important Notes

### 1. Private Endpoint Access

The cluster is configured with a private endpoint, which means:
- **Direct internet access is not available**
- You can only connect from within the same Azure VNet
- Use Azure Bastion, VPN Gateway, or ExpressRoute for external access
- The cluster is accessible from the AKS cluster in the same VNet

### 2. SSL Requirements

- SSL connections are mandatory (`sslmode=require`)
- The cluster will reject non-SSL connections
- Use proper SSL configuration in your applications

### 3. Cost Optimization

The cluster is configured for cost optimization:
- Single coordinator node (no worker nodes)
- Burstable memory-optimized tier
- No high availability or geo-backup
- Can be stopped when not in use to save costs

### 4. Scaling Considerations

When you need to scale:
- Add worker nodes using Azure CLI or portal
- Use Citus distributed tables for horizontal scaling
- Monitor performance and adjust coordinator resources as needed

## Troubleshooting

### Connection Issues

1. **Connection timeout or refused:**
   - Verify you're connecting from within the VNet
   - Check firewall rules if using public access
   - Ensure cluster is in running state

2. **SSL connection errors:**
   - Always use `sslmode=require`
   - For development, you can use `sslmode=require` with `ssl_opts: [verify: :verify_none]`

3. **Authentication failures:**
   - Verify username is `citus`
   - Check administrator password
   - Ensure user has proper permissions

### Performance Issues

1. **Check active queries:**
   ```sql
   SELECT pid, now() - query_start as duration, query 
   FROM pg_stat_activity 
   WHERE state = 'active' 
   ORDER BY duration DESC;
   ```

2. **Monitor resource usage:**
   ```bash
   az cosmosdb postgres cluster show \
     --cluster-name <cluster-name> \
     --resource-group <resource-group> \
     --query "coordinatorVCores"
   ```

3. **Consider scaling if needed:**
   ```bash
   az cosmosdb postgres cluster update \
     --cluster-name <cluster-name> \
     --resource-group <resource-group> \
     --coordinator-v-cores <new-core-count>
   ```

## Security Best Practices

1. **Use Key Vault for secrets:** Store database passwords in Azure Key Vault
2. **Limit network access:** Use private endpoints and restrict firewall rules
3. **Regular updates:** Keep PostgreSQL version updated
4. **Monitor access:** Review connection logs and active sessions regularly
5. **Use least privilege:** Create application-specific database users with minimal permissions

## Related Documentation

- [Azure CosmosDB PostgreSQL Documentation](https://docs.microsoft.com/en-us/azure/cosmos-db/postgresql/)
- [Citus Documentation](https://docs.citusdata.com/)
- [PostgreSQL Documentation](https://www.postgresql.org/docs/)
