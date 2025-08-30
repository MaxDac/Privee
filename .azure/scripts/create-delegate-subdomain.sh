#!/usr/bin/env bash
# create-delegate-subdomain.sh
# Create a child Azure DNS zone (e.g., app.<parent-zone>) and delegate it from the parent zone.

set -euo pipefail

usage() {
  cat <<EOF
Usage:
  $(basename "$0") --rg <RESOURCE_GROUP> --zone <PARENT_ZONE> --subdomain <LABEL> [--ttl 3600]

Examples:
  $(basename "$0") --rg privee-dev-rg --zone privee.northeurope.cloudapp.azure.com --subdomain app

Flags:
  --rg         Resource group containing the DNS zones
  --zone       Parent DNS zone name (e.g., privee.northeurope.cloudapp.azure.com)
  --subdomain  Child subdomain label (e.g., app)
  --ttl        TTL for NS record set in parent (default: 3600)
EOF
}

RG=""
ZONE=""
SUBDOMAIN=""
TTL="3600"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --rg) RG="$2"; shift 2;;
    --zone) ZONE="$2"; shift 2;;
    --subdomain) SUBDOMAIN="$2"; shift 2;;
    --ttl) TTL="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1"; usage; exit 1;;
  esac
done

if [[ -z "$RG" || -z "$ZONE" || -z "$SUBDOMAIN" ]]; then
  echo "Error: --rg, --zone and --subdomain are required." >&2
  usage
  exit 1
fi

CHILD_ZONE="${SUBDOMAIN}.${ZONE}"

echo "Ensuring parent zone '${ZONE}' exists in RG '${RG}'..."
az network dns zone show -g "$RG" -n "$ZONE" >/dev/null 2>&1 || {
  echo "Parent zone not found. Creating..."
  az network dns zone create -g "$RG" -n "$ZONE" -o none
}

echo "Ensuring child zone '${CHILD_ZONE}' exists..."
az network dns zone show -g "$RG" -n "$CHILD_ZONE" >/dev/null 2>&1 || {
  az network dns zone create -g "$RG" -n "$CHILD_ZONE" -o none
}

# Get child NS servers
readarray -t NS_SERVERS < <(az network dns zone show -g "$RG" -n "$CHILD_ZONE" --query nameServers -o tsv)
if [[ ${#NS_SERVERS[@]} -eq 0 ]]; then
  echo "Failed to retrieve child zone nameservers." >&2
  exit 1
fi

echo "Upserting NS record set '${SUBDOMAIN}' in parent zone '${ZONE}' (TTL ${TTL})..."
# Create/ensure the NS record-set exists
az network dns record-set ns show -g "$RG" -z "$ZONE" -n "$SUBDOMAIN" >/dev/null 2>&1 || \
  az network dns record-set ns create -g "$RG" -z "$ZONE" -n "$SUBDOMAIN" --ttl "$TTL" -o none

# Clear existing NS records for a clean state
EXISTING=$(az network dns record-set ns show -g "$RG" -z "$ZONE" -n "$SUBDOMAIN" --query "nsRecords[].nsdname" -o tsv || true)
if [[ -n "$EXISTING" ]]; then
  while IFS= read -r NS; do
    [[ -z "$NS" ]] && continue
    az network dns record-set ns remove-record -g "$RG" -z "$ZONE" -n "$SUBDOMAIN" --nsdname "$NS" -o none || true
  done <<< "$EXISTING"
fi

# Add the child's NS records
for NS in "${NS_SERVERS[@]}"; do
  az network dns record-set ns add-record -g "$RG" -z "$ZONE" -n "$SUBDOMAIN" --nsdname "$NS" -o none
  echo "Delegated NS: $NS"
done

echo "Done. Child zone: $CHILD_ZONE"
az network dns zone show -g "$RG" -n "$CHILD_ZONE" --query "{Id:id,Name:name,NameServers:nameServers}" -o jsonc
