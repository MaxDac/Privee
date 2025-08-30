// Deploy this module at the AKS node resource group's scope
// It creates a user-assigned managed identity, grants Network Contributor on the RG,
// and runs an Azure CLI deployment script to set the DNS label on the ingress Public IP.

@description('Prefix for resource names (letters/numbers).')
param namePrefix string

@description('Location for all resources.')
param location string

@description('DNS label to assign to the ingress Public IP (must be unique per region).')
param ingressDnsLabel string

@description('Optional explicit Public IP resource name to update. If empty, the module selects the first Public IP with an assigned IP and no DNS label, otherwise the first Public IP.')
param ingressPublicIpName string = ''

// Role definition IDs
var networkContributorRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions','b24988ac-6180-42a0-ab88-20f7382dd24c')

// Identity in the same RG (node resource group)
resource uami 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${namePrefix}-ingress-dns-mi'
  location: location
}

// Grant Network Contributor on the node RG to the UAMI
resource uamiRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, 'NetworkContributor', uami.name)
  properties: {
    principalId: uami.properties.principalId
    roleDefinitionId: networkContributorRoleId
    principalType: 'ServicePrincipal'
  }
}

// Deployment script to set the DNS label on the Public IP
resource setDns 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: '${namePrefix}-set-ingress-dnslabel'
  location: location
  kind: 'AzureCLI'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${uami.id}': {}
    }
  }
  properties: {
    azCliVersion: '2.57.0'
    timeout: 'PT10M'
    retentionInterval: 'P1D'
    environmentVariables: [
      {
        name: 'RG'
        value: resourceGroup().name
      }
      {
        name: 'DNS_LABEL'
        value: ingressDnsLabel
      }
      {
        name: 'PIP_NAME'
        value: ingressPublicIpName
      }
    ]
    scriptContent: '''
      set -e
      echo "Node RG: $RG"

      # Wait for at least one Public IP to exist (ingress controller startup)
      for i in $(seq 1 30); do
        COUNT=$(az network public-ip list -g "$RG" --query "length(@)" -o tsv)
        if [ "$COUNT" -gt 0 ]; then break; fi
        echo "Waiting for Public IPs to appear in $RG (attempt $i)..."
        sleep 10
      done

      # 1) Find the PIP attached to the 'kubernetes' Load Balancer
      if [ -z "$PIP_NAME" ]; then
        LB_NAME=$(az network lb list -g "$RG" --query "[?contains(name, 'kubernetes')].name" -o tsv | head -n1 || true)
        if [ -n "$LB_NAME" ]; then
          PIP_ID=$(az network lb show -g "$RG" -n "$LB_NAME" --query "frontendIPConfigurations[?publicIPAddress!=null][0].publicIPAddress.id" -o tsv || true)
          if [ -n "$PIP_ID" ]; then
            PIP_NAME=$(az network public-ip show --ids "$PIP_ID" --query name -o tsv || true)
          fi
        fi
      fi

      if [ -z "$PIP_NAME" ]; then
        echo "ERROR: Could not find a Public IP associated with a 'kubernetes' load balancer in resource group $RG." >&2
        exit 1
      fi

      echo "Chosen Public IP resource: $PIP_NAME"

      # If the desired label already exists on another PIP in this RG, remove it there first
      EXISTING_ON_OTHERS=$(az network public-ip list -g "$RG" \
        --query "[?dnsSettings.domainNameLabel=='$DNS_LABEL' && name!='$PIP_NAME'].name" -o tsv)
      if [ -n "$EXISTING_ON_OTHERS" ]; then
        echo "Found label '$DNS_LABEL' on other Public IP(s): $EXISTING_ON_OTHERS; removing to free the name"
        for N in $EXISTING_ON_OTHERS; do
          az network public-ip update -g "$RG" -n "$N" --remove dnsSettings.domainNameLabel >/dev/null || true
        done
      fi

      echo "Updating Public IP '$PIP_NAME' with DNS label: $DNS_LABEL"
      az network public-ip update -g "$RG" -n "$PIP_NAME" --dns-name "$DNS_LABEL" >/dev/null

      FQDN=$(az network public-ip show -g "$RG" -n "$PIP_NAME" --query "dnsSettings.fqdn" -o tsv)
      echo "Ingress FQDN set to: $FQDN"
    '''
  }
  dependsOn: [ uamiRole ]
}

output dnsLabel string = ingressDnsLabel
