#!/bin/bash
set -euo pipefail

# This script installs and configures cert-manager on a target AKS cluster.

# Defaults
AKS_RG=""
AKS_NAME="privee-aks"
INSTALL_CERT_MANAGER="true"
APPLY_CERT_ISSUERS="true"

usage() {
  cat <<EOF
Usage: $0 [options]
  --aks-rg <rg>                     Resource group where AKS lives (required)
  --aks-name <name>                 AKS cluster name (default: ${AKS_NAME})
  --install-cert-manager <true|false> Install cert-manager from its official manifest (default: ${INSTALL_CERT_MANAGER})
  --apply-cert-issuers <true|false>   Apply the staging and prod ClusterIssuers for Let's Encrypt (default: ${APPLY_CERT_ISSUERS})
  -h, --help                        Show this help
EOF
}

# Parse args
while [[ "${1:-}" != "" ]]; do
  case "$1" in
    --aks-rg) AKS_RG="$2"; shift 2 ;;
    --aks-name) AKS_NAME="$2"; shift 2 ;;
    --install-cert-manager) INSTALL_CERT_MANAGER="$2"; shift 2 ;;
    --apply-cert-issuers) APPLY_CERT_ISSUERS="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown parameter: $1"; usage; exit 1 ;;
  esac
done

if [[ -z "$AKS_RG" ]]; then
    echo "Error: --aks-rg is a required parameter."
    usage
    exit 1
fi

# Resolve paths relative to this script's location
SCRIPT_DIR_REAL_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AZURE_DIR="$(cd "$SCRIPT_DIR_REAL_PATH/.." && pwd)"
CERT_MANAGER_DIR="${AZURE_DIR}/k8s/cert-manager"

echo "Connecting to AKS cluster '$AKS_NAME' in RG '$AKS_RG' to configure cert-manager..."
az aks get-credentials --resource-group "$AKS_RG" --name "$AKS_NAME" --overwrite-existing

if [[ "$INSTALL_CERT_MANAGER" == "true" ]]; then
  echo "Installing cert-manager..."
  kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.15.1/cert-manager.yaml
  echo "Waiting for cert-manager webhook to be ready..."
  kubectl wait --for=condition=available --timeout=300s deployment/cert-manager-webhook -n cert-manager
fi

if [[ "$APPLY_CERT_ISSUERS" == "true" ]]; then
  echo "Applying cert-manager ClusterIssuers..."
  kubectl apply -f "$CERT_MANAGER_DIR/letsencrypt-staging-issuer.yml"
  kubectl apply -f "$CERT_MANAGER_DIR/letsencrypt-prod-issuer.yml"
fi

echo "Cert-manager deployment script finished successfully."
