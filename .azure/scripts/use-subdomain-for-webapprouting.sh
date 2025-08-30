#!/usr/bin/env bash
# use-subdomain-for-webapprouting.sh
# Reconfigure AKS Web App Routing to use a child DNS zone (e.g., app.<zone>)

set -euo pipefail

usage() {
  cat <<EOF
Usage:
  $(basename "$0") --rg <AKS_RG> --cluster <AKS_NAME> --dns-zone-id <CHILD_ZONE_RESOURCE_ID>

Example:
  $(basename "$0") --rg privee-dev-rg --cluster privee-aks \
    --dns-zone-id "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Network/dnsZones/app.privee.northeurope.cloudapp.azure.com"
EOF
}

RG=""
CLUSTER=""
ZONE_ID=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --rg) RG="$2"; shift 2;;
    --cluster) CLUSTER="$2"; shift 2;;
    --dns-zone-id) ZONE_ID="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1"; usage; exit 1;;
  esac
done

if [[ -z "$RG" || -z "$CLUSTER" || -z "$ZONE_ID" ]]; then
  echo "Error: --rg, --cluster, and --dns-zone-id are required." >&2
  usage
  exit 1
fi

echo "Enabling Web App Routing with custom DNS zone..."
az aks addon enable \
  --resource-group "$RG" \
  --name "$CLUSTER" \
  --addon web_application_routing \
  --dns-zone-resource-ids "$ZONE_ID" -o none || {
  # If already enabled, update
  az aks addon update \
    --resource-group "$RG" \
    --name "$CLUSTER" \
    --addon web_application_routing \
    --dns-zone-resource-ids "$ZONE_ID" -o none
}

echo "Done. Current DNS zone IDs:"
az aks show --resource-group "$RG" --name "$CLUSTER" --query "ingressProfile.webAppRouting.dnsZoneResourceIds" -o jsonc
