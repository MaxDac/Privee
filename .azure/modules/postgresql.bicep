@description('PostgreSQL server name (globally unique).')
param pgServerName string

@description('Location for all resources.')
param location string = resourceGroup().location

@description('PostgreSQL admin user')
param pgAdminUser string = 'pgadmin'

@secure()
@description('PostgreSQL admin password')
param pgAdminPassword string

@description('PostgreSQL delegated subnet resource ID')
param pgSubnetId string

@description('Private DNS zone resource ID for PostgreSQL')
param pgPrivateDnsZoneId string

// ----------------- PostgreSQL Flexible Server (Private access) -----------------
resource pg 'Microsoft.DBforPostgreSQL/flexibleServers@2023-03-01-preview' = {
  name: pgServerName
  location: location
  properties: {
    version: '16'
    administratorLogin: pgAdminUser
    administratorLoginPassword: pgAdminPassword
    storage: {
      storageSizeGB: 32
    }
    network: {
      delegatedSubnetResourceId: pgSubnetId
      privateDnsZoneArmResourceId: pgPrivateDnsZoneId
    }
    backup: {
      backupRetentionDays: 7
      geoRedundantBackup: 'Disabled'
    }
    highAvailability: {
      mode: 'Disabled'
    }
    createMode: 'Default'
  }
  sku: {
    name: 'Standard_B1ms'
    tier: 'Burstable'
  }
}

// ----------------- Outputs -----------------
output pgServerId string = pg.id
output pgServerName string = pg.name
output pgServerFqdn string = pg.properties.fullyQualifiedDomainName
