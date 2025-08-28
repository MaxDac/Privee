#!/bin/bash
set -euo pipefail

# Defaults
LOCATION="northeurope"      # Subscription-level deployment location
DEPLOY_RG="privee-dev-rg"   # RG where the identity module will be deployed
NAME_PREFIX="privee"        # Used to compute default ACR name: "<prefix>registry"
ACR_RG=""                   # Defaults to DEPLOY_RG if unset
AKS_RG=""                   # Defaults to DEPLOY_RG if unset
ACR_NAME=""                 # Defaults to "${NAME_PREFIX}registry" (lowercased; matches .azure/modules/acr.bicep)
AKS_NAME="privee-aks"       # Set your AKS name here or override via --aks-name
AKS_KUBELET_OBJECT_ID=""    # Optional: pass kubelet identity objectId to attach ACR pull
GRANT_AKS_ACCESS="true"     # Allow override if you want to skip AKS role assignment
# Role resolution: by default we will try to use the built-in role 'Azure Kubernetes Service RBAC Cluster Admin'
AKS_ROLE_NAME="Azure Kubernetes Service RBAC Cluster Admin"
AKS_ROLE_ID=""              # If provided, takes precedence over AKS_ROLE_NAME

usage() {
  cat <<EOF
Usage: $0 [options]
  -l, --location <azure-region>         Subscription-level deployment location (default: ${LOCATION})
  -g, --resource-group <name>           Resource group to deploy the identity module (default: ${DEPLOY_RG})
  -p, --prefix <namePrefix>             Name prefix (default: ${NAME_PREFIX}); default ACR name becomes <prefix>registry
      --acr-rg <rg>                     Resource group where ACR lives (default: same as --resource-group)
      --aks-rg <rg>                     Resource group where AKS lives (default: same as --resource-group)
      --acr-name <name>                 ACR name (default: <prefix>registry, lowercased)
      --aks-name <name>                 AKS cluster name (default: ${AKS_NAME})
      --aks-kubelet-object-id <id>      Optional kubelet managed identity objectId to grant AcrPull
      --grant-aks-access <true|false>   Whether to create AKS RBAC assignment (default: ${GRANT_AKS_ACCESS})
      --aks-role-name <name>            Optional: RBAC role display name to assign at the AKS scope (default: "${AKS_ROLE_NAME}")
      --aks-role-id <guid>              Optional: Role definition GUID to use. Overrides --aks-role-name if set
  -h, --help                            Show this help
EOF
}

# Parse args
while [[ "${1:-}" != "" ]]; do
  case "$1" in
    -l|--location) LOCATION="$2"; shift 2 ;;
    -g|--resource-group) DEPLOY_RG="$2"; shift 2 ;;
    -p|--prefix) NAME_PREFIX="$2"; shift 2 ;;
    --acr-rg) ACR_RG="$2"; shift 2 ;;
    --aks-rg) AKS_RG="$2"; shift 2 ;;
    --acr-name) ACR_NAME="$2"; shift 2 ;;
    --aks-name) AKS_NAME="$2"; shift 2 ;;
    --aks-kubelet-object-id) AKS_KUBELET_OBJECT_ID="$2"; shift 2 ;;
    --grant-aks-access) GRANT_AKS_ACCESS="$2"; shift 2 ;;
    --aks-role-name) AKS_ROLE_NAME="$2"; shift 2 ;;
    --aks-role-id) AKS_ROLE_ID="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown parameter: $1"; usage; exit 1 ;;
  esac
done

# Derived defaults
ACR_RG="${ACR_RG:-$DEPLOY_RG}"
AKS_RG="${AKS_RG:-$DEPLOY_RG}"
ACR_NAME="${ACR_NAME:-$(echo "${NAME_PREFIX}registry" | tr '[:upper:]' '[:lower:]')}"

# Resolve paths
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SUB_BICEP="${SCRIPT_DIR}/main-subscription.bicep"
SUB_ARM="${SCRIPT_DIR}/main-subscription.json"
SUB_PARAMS="${SCRIPT_DIR}/main.parameters.json"
IDENTITY_BICEP="${SCRIPT_DIR}/modules/gha-oidc-identity.bicep"

# Check Azure login
if ! az account show > /dev/null 2>&1; then
  echo "You are not logged in to Azure. Please run 'az login' to authenticate."
  exit 1
fi

echo "Building subscription-level Bicep..."
az bicep build --file "$SUB_BICEP" --outfile "$SUB_ARM"

echo "Deploying subscription-level resources to location '$LOCATION'..."
az deployment sub create \
  --name "privee-main-deployment" \
  --location "$LOCATION" \
  --template-file "$SUB_ARM" \
  --parameters "$SUB_PARAMS"

# Ensure deployment RG exists before group-level deployments
echo "Ensuring resource group '$DEPLOY_RG' exists in '$LOCATION'..."
az group create -n "$DEPLOY_RG" -l "$LOCATION" >/dev/null

# Verify ACR exists; auto-detect RG if needed
echo "Validating ACR '$ACR_NAME'..."
if ! az acr show -n "$ACR_NAME" -g "$ACR_RG" >/dev/null 2>&1; then
  echo "ACR '$ACR_NAME' not found in RG '$ACR_RG'. Searching subscription by name..."
  ACR_INFO="$(az acr list --query "[?name=='$ACR_NAME'].{rg:resourceGroup,name:name}" -o tsv)"
  if [[ -n "$ACR_INFO" ]]; then
    ACR_RG_FOUND="$(echo "$ACR_INFO" | awk '{print $1}')"
    echo "Found ACR '$ACR_NAME' in RG '$ACR_RG_FOUND'. Using that."
    ACR_RG="$ACR_RG_FOUND"
  else
    echo "ERROR: ACR '$ACR_NAME' not found in subscription."
    echo "Hint: Create it first or pass --acr-name and/or --acr-rg to match existing resources."
    exit 1
  fi
fi

# Verify AKS exists; auto-detect RG if needed (only if we will grant AKS access)
if [[ "$GRANT_AKS_ACCESS" == "true" ]]; then
  echo "Validating AKS '$AKS_NAME'..."
  if ! az aks show -n "$AKS_NAME" -g "$AKS_RG" >/dev/null 2>&1; then
    echo "AKS '$AKS_NAME' not found in RG '$AKS_RG'. Searching subscription by name..."
    AKS_INFO="$(az aks list --query "[?name=='$AKS_NAME'].{rg:resourceGroup,name:name}" -o tsv)"
    if [[ -n "$AKS_INFO" ]]; then
      AKS_RG_FOUND="$(echo "$AKS_INFO" | awk '{print $1}')"
      echo "Found AKS '$AKS_NAME' in RG '$AKS_RG_FOUND'. Using that."
      AKS_RG="$AKS_RG_FOUND"
    else
      echo "ERROR: AKS '$AKS_NAME' not found in subscription."
      echo "Hint: Create it first or pass --aks-name and/or --aks-rg to match existing resources,"
      echo "      or rerun with --grant-aks-access false to skip AKS RBAC assignment."
      exit 1
    fi
  fi

  # Auto-populate kubelet identity if not provided
  if [[ -z "$AKS_KUBELET_OBJECT_ID" ]]; then
    AKS_KUBELET_OBJECT_ID="$(az aks show -n "$AKS_NAME" -g "$AKS_RG" --query "identityProfile.kubeletidentity.objectId" -o tsv 2>/dev/null || true)"
    if [[ -n "$AKS_KUBELET_OBJECT_ID" ]]; then
      echo "Detected AKS kubelet identity objectId: $AKS_KUBELET_OBJECT_ID"
    else
      echo "Warning: Could not detect kubelet identity objectId; skipping ACR pull binding."
    fi
  fi

  # Resolve the AKS RBAC role definition ID if not explicitly provided
  if [[ -z "$AKS_ROLE_ID" ]]; then
    # Try exact match first
    AKS_ROLE_ID="$(az role definition list --name "$AKS_ROLE_NAME" --query "[0].name" -o tsv 2>/dev/null || true)"
    # Fallbacks if not found
    if [[ -z "$AKS_ROLE_ID" ]]; then
      # Try common alternative display names
      for alt in \
        "Azure Kubernetes Service RBAC Admin" \
        "Azure Kubernetes Service RBAC Cluster Admin" \
        "Azure Kubernetes Service RBAC Owner"; do
        AKS_ROLE_ID="$(az role definition list --name "$alt" --query "[0].name" -o tsv 2>/dev/null || true)"
        if [[ -n "$AKS_ROLE_ID" ]]; then
          echo "Resolved AKS role using alternative name: $alt -> $AKS_ROLE_ID"
          break
        fi
      done
    else
      echo "Resolved AKS role '$AKS_ROLE_NAME' -> $AKS_ROLE_ID"
    fi

    if [[ -z "$AKS_ROLE_ID" ]]; then
      echo "Warning: Could not resolve an AKS RBAC role definition ID in this subscription."
      echo "         The deployment will proceed without assigning AKS RBAC (grantAksAccess=false)."
      GRANT_AKS_ACCESS="false"
    fi
  else
    echo "Using provided AKS role definition ID: $AKS_ROLE_ID"
  fi
fi

# Build common parameter list for group deployment
PARAMS=(
  namePrefix="$NAME_PREFIX"
  githubOwner="MaxDac"
  githubRepo="Privee"
  oidcSubject="ref:refs/heads/main"
  acrResourceGroup="$ACR_RG"
  acrName="$ACR_NAME"
  aksResourceGroup="$AKS_RG"
  aksName="$AKS_NAME"
  grantAksAccess=$GRANT_AKS_ACCESS
)
if [[ -n "$AKS_KUBELET_OBJECT_ID" ]]; then
  PARAMS+=( aksKubeletIdentityObjectId="$AKS_KUBELET_OBJECT_ID" )
fi
if [[ "$GRANT_AKS_ACCESS" == "true" && -n "$AKS_ROLE_ID" ]]; then
  PARAMS+=( aksRoleDefinitionId="$AKS_ROLE_ID" )
fi

echo "Summary of resolved targets:"
echo "  Deployment RG:         $DEPLOY_RG"
echo "  ACR:                   $ACR_NAME (rg: $ACR_RG)"
if [[ "$GRANT_AKS_ACCESS" == "true" ]]; then
  echo "  AKS:                   $AKS_NAME (rg: $AKS_RG)"
  echo "  Kubelet Object ID:     ${AKS_KUBELET_OBJECT_ID:-<not provided/detected>}"
  echo "  AKS Role Definition:   ${AKS_ROLE_ID:-<default in module>}"
else
  echo "  AKS RBAC assignment:   skipped (grantAksAccess=false)"
fi

echo "What-if: group deployment for OIDC identity + role assignments into RG '$DEPLOY_RG'..."
az deployment group what-if \
  -g "$DEPLOY_RG" \
  -f "$IDENTITY_BICEP" \
  -p "${PARAMS[@]}" || true

echo "Deploying OIDC identity + role assignments into RG '$DEPLOY_RG'..."
set +e
DEPLOY_OUTPUT=$(az deployment group create \
  -g "$DEPLOY_RG" \
  -f "$IDENTITY_BICEP" \
  -p "${PARAMS[@]}" 2>&1)
DEPLOY_EXIT=$?
set -e

if [[ $DEPLOY_EXIT -ne 0 ]]; then
  echo "$DEPLOY_OUTPUT" | tee "$SCRIPT_DIR/error.log" >&2 || true
  if echo "$DEPLOY_OUTPUT" | grep -q "RoleAssignmentExists"; then
    echo "Note: One or more role assignments already existed. Treating as non-fatal and continuing."
  else
    echo "Deployment failed. See $SCRIPT_DIR/error.log for details." >&2
    exit $DEPLOY_EXIT
  fi
fi

echo
echo "Deployment completed successfully."
echo "Useful values for GitHub Actions:"
echo "  AZURE_TENANT_ID         -> \$(az account show --query tenantId -o tsv)"
echo "  AZURE_SUBSCRIPTION_ID   -> \$(az account show --query id -o tsv)"
echo "  AZURE_CLIENT_ID         -> from deployment outputs (clientId)"
echo "  ACR_LOGIN_SERVER        -> \$(az acr show -n \"$ACR_NAME\" -g \"$ACR_RG\" --query loginServer -o tsv)"