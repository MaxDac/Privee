@description('Prefix for resource names (letters/numbers).')
param namePrefix string

@description('Location for all resources.')
param location string = resourceGroup().location

@allowed(['Basic','Standard','Premium'])
@description('SKU for Azure Container Registry.')
param acrSku string = 'Standard'

var acrName = toLower('${namePrefix}registry')

// ----------------- ACR -----------------
resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: acrName
  location: location
  sku: { name: acrSku }
  properties: {
    adminUserEnabled: false
    publicNetworkAccess: 'Enabled'
  }
}

// ----------------- Outputs -----------------
output acrId string = acr.id
output acrName string = acr.name
output acrLoginServer string = '${acr.name}.azurecr.io'
