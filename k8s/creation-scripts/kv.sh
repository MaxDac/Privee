echo "🚀 Starting Azure Key Vault and Workload Identity setup..."
echo "📋 Setting up environment variables..."

export REGION="northeurope"
export AKS_RG="Privee"
export AKS_NAME="Privee"
export KV_RG="Privee-KV"
export KV_NAME="Privee-KV"
export NAMESPACE="default"
export SA_NAME="privee-kv-sa"

echo "✅ Environment variables configured:"
echo "   - Region: $REGION"
echo "   - AKS Resource Group: $AKS_RG"
echo "   - AKS Name: $AKS_NAME"
echo "   - Key Vault Resource Group: $KV_RG"
echo "   - Key Vault Name: $KV_NAME"
echo ""

echo "🔐 Creating the Key Vault..."
az keyvault create \
    --name Privee-KV \
    --resource-group Privee-KV \
    --location northeurope

if [ $? -eq 0 ]; then
    echo "✅ Key Vault created successfully!"
else
    echo "❌ Failed to create Key Vault or it already exists"
fi
echo ""

echo "🔧 Enabling OIDC and Workload Identity on the AKS cluster..."
az aks update \
    -g Privee \
    -n Privee \
    --enable-oidc-issuer \
    --enable-workload-identity

if [ $? -eq 0 ]; then
    echo "✅ OIDC and Workload Identity enabled on AKS cluster!"
else
    echo "❌ Failed to enable OIDC and Workload Identity"
fi
echo ""

echo "🔌 Enabling AKV Secrets Provider add-on (CSI driver + provider)..."
az aks enable-addons -g "$AKS_RG" -n "$AKS_NAME" --addons azure-keyvault-secrets-provider

if [ $? -eq 0 ]; then
    echo "✅ AKV Secrets Provider add-on enabled!"
else
    echo "❌ Failed to enable AKV Secrets Provider add-on"
fi
echo ""

echo "👤 Assigning Key Vault Administrator role to current user..."
az role assignment create \
  --role "Key Vault Administrator" \
  --assignee $(az ad signed-in-user show --query id -o tsv) \
  --scope $(az keyvault show --name privee-kv --query id -o tsv)

if [ $? -eq 0 ]; then
    echo "✅ Key Vault Administrator role assigned to current user!"
else
    echo "❌ Failed to assign Key Vault Administrator role"
fi
echo ""

echo "🔗 Getting AKS OIDC Issuer URL..."
AKS_OIDC_ISSUER="$(az aks show -g Privee -n Privee --query "oidcIssuerProfile.issuerUrl" -o tsv)"
echo "✅ AKS OIDC Issuer URL: $AKS_OIDC_ISSUER"
echo ""

echo "🆔 Creating User Assigned Managed Identity for workload access to Key Vault..."
if ! az identity show -g "$AKS_RG" -n "privee-kv-wi" >/dev/null 2>&1; then
    echo "⚠️  Identity does not exist, creating new one..."
    az identity create -g "$AKS_RG" -n "privee-kv-wi" -l "$REGION"
    if [ $? -eq 0 ]; then
        echo "✅ User Assigned Managed Identity created!"
    else
        echo "❌ Failed to create User Assigned Managed Identity"
    fi
else
    echo "ℹ️  Identity 'privee-kv-wi' already exists, skipping creation"
fi
echo ""

echo "🔍 Retrieving User Assigned Managed Identity details..."

export UAMI_CLIENT_ID="$(az identity show -g "$AKS_RG" -n "privee-kv-wi" --query clientId -o tsv)"
export UAMI_PRINCIPAL_ID="$(az identity show -g "$AKS_RG" -n "privee-kv-wi" --query principalId -o tsv)"

echo "✅ UAMI Client ID: $UAMI_CLIENT_ID"
echo "✅ UAMI Principal ID: $UAMI_PRINCIPAL_ID"
echo ""

echo "🔐 Granting UAMI access to Key Vault..."
export KV_ID="$(az keyvault show -g "$KV_RG" -n "$KV_NAME" --query id -o tsv)"
az role assignment create --assignee-object-id "$UAMI_PRINCIPAL_ID" --assignee-principal-type ServicePrincipal --role "Key Vault Secrets User" --scope "$KV_ID" >/dev/null 2>&1 || true
az role assignment create --assignee-object-id "$UAMI_PRINCIPAL_ID" --assignee-principal-type ServicePrincipal --role "Key Vault Reader" --scope "$KV_ID" >/dev/null 2>&1 || true

echo "✅ Key Vault access roles assigned to UAMI:"
echo "   - Key Vault Secrets User"
echo "   - Key Vault Reader"
echo ""

echo "🔗 Binding UAMI to Kubernetes ServiceAccount via federated credential..."
export SUBJECT="system:serviceaccount:${NAMESPACE}:${SA_NAME}"
az identity federated-credential create --name "privee-kv-wi-fic" --identity-name "privee-kv-wi" --resource-group "$AKS_RG" --issuer "$AKS_OIDC_ISSUER" --subject "$SUBJECT" --audience "api://AzureADTokenExchange" >/dev/null 2>&1 || true

echo "✅ Federated credential created for subject: $SUBJECT"
echo ""

echo "🎛️  Creating Kubernetes namespace and ServiceAccount..."
kubectl get ns "$NAMESPACE" >/dev/null 2>&1 || kubectl create namespace "$NAMESPACE"
if [ $? -eq 0 ]; then
    echo "✅ Namespace '$NAMESPACE' is ready"
else
    echo "❌ Failed to create/verify namespace '$NAMESPACE'"
fi

kubectl -n "$NAMESPACE" get sa "$SA_NAME" >/dev/null 2>&1 || kubectl -n "$NAMESPACE" create sa "$SA_NAME"
if [ $? -eq 0 ]; then
    echo "✅ ServiceAccount '$SA_NAME' is ready"
else
    echo "❌ Failed to create/verify ServiceAccount '$SA_NAME'"
fi

kubectl -n "$NAMESPACE" annotate sa "$SA_NAME" azure.workload.identity/use=true --overwrite
kubectl -n "$NAMESPACE" annotate sa "$SA_NAME" azure.workload.identity/client-id="$UAMI_CLIENT_ID" --overwrite
if [ $? -eq 0 ]; then
    echo "✅ ServiceAccount annotated for Workload Identity"
else
    echo "❌ Failed to annotate ServiceAccount"
fi
echo ""

echo "📜 Setting up certificate management..."
## Certificate settings
KV_NAME="Privee-KV"
CERT_NAME="privee-tls"
DNS_NAME="privee.northeurope.cloudapp.azure.com"

echo "📋 Certificate configuration:"
echo "   - Key Vault: $KV_NAME"
echo "   - Certificate Name: $CERT_NAME"
echo "   - DNS Name: $DNS_NAME"
echo ""

echo "📧 Adding certificate contact for notifications..."
az keyvault certificate contact add \
  --vault-name "$KV_NAME" \
  --email "massimiliano.dacunzo@hotmail.com" >/dev/null 2>&1

if [ $? -eq 0 ]; then
    echo "✅ Certificate contact added successfully"
else
    echo "ℹ️  Certificate contact already exists or failed to add (this is expected if contact exists)"
fi
echo ""

echo "📜 Creating the certificate (first issuance will happen immediately)..."
az keyvault certificate create \
  --vault-name "$KV_NAME" \
  --name "$CERT_NAME" \
  --policy @cert-policy.json

if [ $? -eq 0 ]; then
    echo "✅ Certificate created successfully!"
else
    echo "❌ Failed to create certificate"
fi
echo ""

echo "📊 Displaying certificate details..."
az keyvault certificate show \
  --vault-name "$KV_NAME" \
  --name "$CERT_NAME" -o table

echo ""
echo "🎉 Azure Key Vault and Workload Identity setup completed!"
echo "📝 Next steps:"
echo "   1. Deploy the SecretProviderClass resource"
echo "   2. Deploy the application pod with the service account"
echo "   3. Verify the certificate sync to Kubernetes secrets"