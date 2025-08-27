# Variables
RG=<yourResourceGroup>
AKS=${namePrefix}-aks
KV=$(az deployment group show -g $RG -n main --query "properties.outputs.keyVaultName.value" -o tsv)
ZONEID=$(az deployment group show -g $RG -n main --query "properties.outputs.dnsZoneId.value" -o tsv)

# 2.1 Enable the Application Routing add‑on on the existing cluster
az aks approuting enable -g $RG -n $AKS   # or --enable-app-routing at create time [2](https://learn.microsoft.com/en-us/azure/aks/app-routing)

# 2.2 Attach Key Vault to the add‑on and enable Key Vault provider (Secrets Store CSI)
az aks approuting update -g $RG -n $AKS --enable-kv --attach-kv $(az keyvault show -n $KV --query id -o tsv)
# (Enables cert reload by CSI autorotation as per docs) [1](https://learn.microsoft.com/en-us/azure/aks/app-routing-dns-ssl)

# 2.3 Attach your Azure DNS zone so external-dns in the add‑on can manage host A records
az aks approuting update -g $RG -n $AKS --attach-dns-zone $ZONEID