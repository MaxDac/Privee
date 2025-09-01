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
  echo "Waiting for cert-manager CRDs to be registered..."
  # Wait for essential CRDs to exist before applying any custom resources
  CRDS=(
    certificates.cert-manager.io
    certificaterequests.cert-manager.io
    clusterissuers.cert-manager.io
    issuers.cert-manager.io
    challenges.acme.cert-manager.io
    orders.acme.cert-manager.io
  )
  for crd in "${CRDS[@]}"; do
    echo -n "  Waiting for CRD $crd ... "
    for i in {1..120}; do
      if kubectl get crd "$crd" >/dev/null 2>&1; then
        echo "OK"
        break
      fi
      sleep 2
      if [[ $i -eq 120 ]]; then
        echo
        echo "ERROR: Timed out waiting for CRD $crd to be created."
        exit 1
      fi
    done
  done

  echo "Waiting for cert-manager deployments to become available..."
  kubectl wait --for=condition=available --timeout=300s deployment/cert-manager -n cert-manager
  kubectl wait --for=condition=available --timeout=300s deployment/cert-manager-cainjector -n cert-manager
  kubectl wait --for=condition=available --timeout=300s deployment/cert-manager-webhook -n cert-manager

  echo "Verifying webhook service endpoints..."
  # Ensure the webhook service has ready endpoints to avoid webhook connection EOFs
  for i in {1..60}; do
    EP_COUNT=$(kubectl -n cert-manager get endpoints cert-manager-webhook -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null | awk 'NF{c++} END{print c+0}')
    if [[ "${EP_COUNT:-0}" -gt 0 ]]; then
      echo "  cert-manager-webhook has ${EP_COUNT} ready endpoint(s)."
      break
    fi
    sleep 2
    if [[ $i -eq 60 ]]; then
      echo "WARNING: Webhook endpoints not reported as ready; proceeding but issuer apply may fail."
    fi
  done
fi

if [[ "$APPLY_CERT_ISSUERS" == "true" ]]; then
  echo "Applying cert-manager ClusterIssuers..."
  # Apply with simple retry to handle transient webhook startup races
  for issuer in "$CERT_MANAGER_DIR/letsencrypt-staging-issuer.yml" "$CERT_MANAGER_DIR/letsencrypt-prod-issuer.yml"; do
    for attempt in {1..5}; do
      if kubectl apply -f "$issuer"; then
        echo "Applied $issuer"
        break
      fi
      echo "Retry $attempt/5 applying $issuer after webhook readiness..."
      sleep 5
      if [[ $attempt -eq 5 ]]; then
        echo "ERROR: Failed to apply $issuer after retries."
        exit 1
      fi
    done
  done
fi

echo "Cert-manager deployment script finished successfully."
