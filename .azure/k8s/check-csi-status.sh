#!/bin/bash

# Script to check CSI driver status and troubleshoot issues

echo "=== CSI Driver Status Check ==="

# Check if the add-on is enabled
echo "1. Checking if Azure Key Vault provider is enabled..."
CSI_ENABLED=$(az aks show --resource-group privee-dev-rg --name privee-aks --query "addonProfiles.azureKeyvaultSecretsProvider.enabled" -o tsv 2>/dev/null || echo "false")
echo "CSI Driver enabled: $CSI_ENABLED"

# Check CSI driver pods in kube-system namespace
echo ""
echo "2. Checking CSI driver pods..."
echo "Secrets Store CSI Driver pods:"
kubectl get pods -n kube-system -l app=secrets-store-csi-driver

echo ""
echo "Azure provider pods:"
kubectl get pods -n kube-system -l app=secrets-store-provider-azure

# Check if CRD is installed
echo ""
echo "3. Checking SecretProviderClass CRD..."
if kubectl get crd secretproviderclasses.secrets-store.csi.x-k8s.io > /dev/null 2>&1; then
    echo "✓ SecretProviderClass CRD is installed"
    kubectl get crd secretproviderclasses.secrets-store.csi.x-k8s.io -o jsonpath='{.metadata.creationTimestamp}' && echo ""
else
    echo "✗ SecretProviderClass CRD is NOT installed"
fi

# Check existing SecretProviderClasses
echo ""
echo "4. Checking existing SecretProviderClasses..."
kubectl get secretproviderclass -A

# Check CSI driver registration
echo ""
echo "5. Checking CSI driver registration..."
kubectl get csidriver | grep secrets-store

echo ""
echo "=== Troubleshooting Commands ==="
echo "If CSI driver is not working, try:"
echo "1. Restart CSI driver pods:"
echo "   kubectl delete pods -n kube-system -l app=secrets-store-csi-driver"
echo "   kubectl delete pods -n kube-system -l app=secrets-store-provider-azure"
echo ""
echo "2. Check CSI driver logs:"
echo "   kubectl logs -n kube-system -l app=secrets-store-csi-driver"
echo "   kubectl logs -n kube-system -l app=secrets-store-provider-azure"
echo ""
echo "3. Re-enable the add-on:"
echo "   az aks disable-addons --resource-group privee-dev-rg --name privee-aks --addons azure-keyvault-secrets-provider"
echo "   az aks enable-addons --resource-group privee-dev-rg --name privee-aks --addons azure-keyvault-secrets-provider"