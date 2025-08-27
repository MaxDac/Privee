@description('Prefix for resource names (letters/numbers).')
param namePrefix string

@description('Location for all resources.')
param location string = resourceGroup().location

@description('VNet CIDR')
param vnetCidr string = '10.0.0.0/16'

@description('AKS subnet CIDR')
param aksSubnetCidr string = '10.0.1.0/24'

@description('PostgreSQL delegated subnet CIDR')
param pgSubnetCidr string = '10.0.2.0/24'

@description('Public Azure DNS zone to host your app domain (e.g., example.com).')
param dnsZoneName string

@description('PostgreSQL server name (globally unique).')
param pgServerName string

var vnetName = '${namePrefix}-vnet'
var aksSubnetName = '${namePrefix}-aks-subnet'
var pgSubnetName = 'pg-subnet'
var pgPrivateDnsZoneName = '${pgServerName}.private.postgres.database.azure.com'

// ----------------- Networking -----------------
resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: { addressPrefixes: [ vnetCidr ] }
    subnets: [
      {
        name: aksSubnetName
        properties: {
          addressPrefix: aksSubnetCidr
        }
      }
      {
        name: pgSubnetName
        properties: {
          addressPrefix: pgSubnetCidr
          delegations: [
            {
              name: 'pg-delegation'
              properties: {
                serviceName: 'Microsoft.DBforPostgreSQL/flexibleServers' // Required for VNet-injected PG FS
              }
            }
          ]
        }
      }
    ]
  }
}

// Optional NSG to limit DB to AKS subnet only
resource pgNsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: '${namePrefix}-pg-nsg'
  location: location
  properties: {
    securityRules: [
      {
        name: 'allow-aks-to-pg-5432'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          sourceAddressPrefixes: [ aksSubnetCidr ]
          destinationAddressPrefix: '*'
          destinationPortRange: '5432'
        }
      }
    ]
  }
}

// Note: NSG association is handled via subnet properties in the VNet resource above

// Private DNS zone for PG Flexible Server (private access mode requires a private DNS zone linked to VNet)
resource pgPrivDns 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: pgPrivateDnsZoneName
  location: 'global'
}

resource pgPrivDnsLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: pgPrivDns
  name: '${namePrefix}-pgdns-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: { id: vnet.id }
  }
}

// Public DNS zone for your app hosts; the add-on will create A records in this zone
resource publicZone 'Microsoft.Network/dnsZones@2018-05-01' = {
  name: dnsZoneName
  location: 'global'
}

// ----------------- Outputs -----------------
output vnetId string = vnet.id
output vnetName string = vnet.name
output aksSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnetName, aksSubnetName)
output pgSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnetName, pgSubnetName)
output pgPrivateDnsZoneId string = pgPrivDns.id
output publicDnsZoneId string = publicZone.id
