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

      # Helper: join lines into space-delimited string
      join_lines() {
        tr '\n' ' ' | xargs
      }

      # Poll for an ingress Public IP (exclude outbound LB public IPs)
      # Up to ~15 minutes (90 x 10s)
      for i in $(seq 1 90); do
        echo "[attempt $i] Inspecting load balancers and public IPs in $RG..."

        # Identify outbound LBs (those having outboundRules)
        OUTBOUND_LB_IDS=$(az network lb list -g "$RG" --query "[?length(outboundRules)>0].id" -o tsv 2>/dev/null || true)
        OUTBOUND_PIP_IDS=""
        if [ -n "$OUTBOUND_LB_IDS" ]; then
          while IFS= read -r LB_ID; do
            [ -z "$LB_ID" ] && continue
            PIPS=$(az network lb show --ids "$LB_ID" --query "frontendIPConfigurations[?publicIPAddress!=null].[].publicIPAddress.id" -o tsv 2>/dev/null || true)
            if [ -n "$PIPS" ]; then
              OUTBOUND_PIP_IDS=$(printf "%s\n%s" "$OUTBOUND_PIP_IDS" "$PIPS")
            fi
          done <<< "$OUTBOUND_LB_IDS"
        fi

        # Gather candidate PIPs: those associated to any LB frontend and not part of outbound LBs
        CANDIDATE_IDS=$(az network public-ip list -g "$RG" --query "[?ipConfiguration!=null].id" -o tsv 2>/dev/null || true)
        SELECTED_ID=""

        # Prefer PIPs whose name contains 'kubernetes' or 'ingress' or 'app-routing'
        if [ -n "$CANDIDATE_IDS" ]; then
          while IFS= read -r PID; do
            [ -z "$PID" ] && continue
            # Skip if belongs to outbound LB set
            if echo "$OUTBOUND_PIP_IDS" | grep -q "$PID"; then
              continue
            fi
            NAME=$(az network public-ip show --ids "$PID" --query name -o tsv 2>/dev/null || true)
            if echo "$NAME" | grep -qiE 'kubernetes|ingress|app-routing'; then
              SELECTED_ID="$PID"
              break
            fi
          done <<< "$CANDIDATE_IDS"
        fi

        # Fallback: pick the first non-outbound candidate if none matched by name
        if [ -z "$SELECTED_ID" ] && [ -n "$CANDIDATE_IDS" ]; then
          while IFS= read -r PID; do
            [ -z "$PID" ] && continue
            if echo "$OUTBOUND_PIP_IDS" | grep -q "$PID"; then
              continue
            fi
            SELECTED_ID="$PID"
            break
          done <<< "$CANDIDATE_IDS"
        fi

        # If parameter provided, override discovery
        if [ -n "$PIP_NAME" ]; then
          echo "PIP_NAME provided via parameter: $PIP_NAME"
          SELECTED_ID=$(az network public-ip show -g "$RG" -n "$PIP_NAME" --query id -o tsv 2>/dev/null || true)
        fi

        if [ -n "$SELECTED_ID" ]; then
          PIP_NAME=$(az network public-ip show --ids "$SELECTED_ID" --query name -o tsv)
          echo "Chosen Public IP resource: $PIP_NAME"
          break
        fi

        echo "Waiting for ingress Public IP to be created (or attached) in $RG..."
        sleep 10
      done

      if [ -z "$PIP_NAME" ]; then
        echo "ERROR: Could not discover an ingress Public IP in resource group $RG. Ensure the Web App Routing add-on is enabled and the ingress Service has provisioned a public IP." >&2
        exit 1
      fi

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
