@description('CosmosDB PostgreSQL cluster name (globally unique).')
param clusterName string

@description('Location for all resources.')
param location string = resourceGroup().location

@secure()
@description('PostgreSQL admin password')
param administratorPassword string

@description('CosmosDB PostgreSQL subnet resource ID')
param cosmosSubnetId string

@description('Private DNS zone resource ID for CosmosDB PostgreSQL')
param cosmosPrivateDnsZoneId string

// ----------------- CosmosDB for PostgreSQL Cluster (Single Node - Cost Optimized) -----------------
resource cosmosDbPostgreCluster 'Microsoft.DBforPostgreSQL/serverGroupsv2@2023-03-02-preview' = {
  name: clusterName
  location: location
  properties: {
    // Database and authentication configuration
    databaseName: 'privee'
    administratorLoginPassword: administratorPassword
    
    // High availability and backup - Disabled for cost optimization
    enableHa: false
    enableGeoBackup: false
    
    // Database version
    postgresqlVersion: '16'
    
    // Coordinator (main node) configuration - Burstable tier for cost optimization
    coordinatorVCores: 1  // Note: lowercase 'c' as per Portal template
    coordinatorStorageQuotaInMb: 32768  // 32 GiB
    coordinatorServerEdition: 'BurstableMemoryOptimized'
    
    // Single node configuration (most cost-effective)
    nodeCount: 0
    nodeVCores: 4  // Default worker node config (not used with nodeCount: 0)
    nodeStorageQuotaInMb: 524288  // Default worker storage (not used with nodeCount: 0)
    nodeServerEdition: 'MemoryOptimized'  // As per Portal template
    nodeEnablePublicIpAccess: false  // As per Portal template
  }
}

// Note: Extensions like 'citext' are supported in CosmosDB PostgreSQL but must be enabled 
// using SQL commands after cluster deployment. Connect to the database and run:
// CREATE EXTENSION IF NOT EXISTS citext;
// 
// This is different from regular PostgreSQL Flexible Servers where extensions can be 
// pre-configured via Bicep using the azure.extensions configuration parameter.

// ----------------- Private Endpoint for Coordinator Node -----------------
// NOTE: Private endpoint configuration is placed here (not in networking module) because:
// 1. The private endpoint must reference the actual CosmosDB cluster resource (cosmosDbPostgreCluster.id)
// 2. The cluster must exist before the private endpoint can be created
// 3. Moving this to networking module would create a circular dependency issue
// 4. This follows Azure best practices where private endpoints are created alongside their target resources
resource privateEndpoint 'Microsoft.Network/privateEndpoints@2020-03-01' = {
  name: '${clusterName}-c-pe1'  // Match Portal naming convention
  location: location
  properties: {
    subnet: {
      id: cosmosSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: '${clusterName}-c-pe1'  // Match Portal naming
        properties: {
          privateLinkServiceId: cosmosDbPostgreCluster.id
          groupIds: [
            'coordinator'
          ]
        }
      }
    ]
  }
}

// ----------------- Private DNS Zone Group -----------------
resource privateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2020-03-01' = {
  parent: privateEndpoint
  name: 'default'  // Match Portal template naming
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink.postgres.cosmos.azure.com'  // Match Portal template naming
        properties: {
          privateDnsZoneId: cosmosPrivateDnsZoneId
        }
      }
    ]
  }
}

// ----------------- Outputs -----------------
output clusterId string = cosmosDbPostgreCluster.id
output clusterName string = cosmosDbPostgreCluster.name
output databaseName string = cosmosDbPostgreCluster.properties.databaseName
output serverNames array = cosmosDbPostgreCluster.properties.serverNames
output coordinatorEndpoint string = cosmosDbPostgreCluster.properties.serverNames[0].fullyQualifiedDomainName
output administratorLogin string = 'citus'  // Fixed value for CosmosDB PostgreSQL
output privateEndpointId string = privateEndpoint.id
// Use the coordinator endpoint as the private FQDN since it's accessible via private endpoint
output privateEndpointFqdn string = cosmosDbPostgreCluster.properties.serverNames[0].fullyQualifiedDomainName
