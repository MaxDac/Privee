#!/usr/bin/env bash
set -euo pipefail

# Main orchestrator for Privee AKS + NGINX Ingress with static IP deployment
# Run from the k8s/ folder

echo "🚀 Starting Privee deployment to AKS..."

# 1. Create resource groups
echo "📁 Creating resource groups..."
./creation-scripts/resource-groups.sh

# 2. Create AKS cluster and VNet
echo "🏗️  Creating AKS cluster..."
./creation-scripts/cluster.sh

# 3. Set up static public IP for ingress
echo "🌐 Setting up static public IP..."
./creation-scripts/setup-azure-ip.sh

# 4. Create Key Vault and configure Workload Identity
echo "🔐 Setting up Key Vault and Workload Identity..."
./creation-scripts/kv.sh

# 6. Get AKS credentials
echo "🔑 Getting AKS credentials..."
az aks get-credentials -g Privee -n Privee --overwrite-existing

# 7. Set up NGINX Ingress Controller with static IP
echo "🔧 Setting up NGINX Ingress Controller with static IP..."
./creation-scripts/ingress.sh

# 8. Verify NGINX Ingress Controller status
echo "🔍 Verifying NGINX Ingress Controller status..."
./creation-scripts/setup-ingress-with-ip.sh

# 9. Deploy secrets
echo "🔒 Deploying secrets..."
kubectl apply -f deployments/secrets.yml

# 10. Deploy app and services
echo "🚀 Deploying application and services..."
kubectl apply -f deployments/deployment.yml
kubectl apply -f deployments/headless-service.yml

# 11. Deploy SecretProviderClass and sync pod
echo "🔗 Setting up SecretProviderClass..."
TENANT_ID=$(az account show --query tenantId -o tsv)
UAMI_CLIENT_ID=$(az identity show -g Privee -n privee-kv-wi --query clientId -o tsv)
echo "   - Tenant ID: $TENANT_ID"
echo "   - UAMI Client ID: $UAMI_CLIENT_ID"
sed "s/<YOUR_TENANT_ID>/$TENANT_ID/g; s/<YOUR_UAMI_CLIENT_ID>/$UAMI_CLIENT_ID/g" deployments/secret-provider-class.yml | kubectl apply -f -
kubectl apply -f deployments/spc-sync-pod.yml

# 12. Deploy ingress (NGINX with static IP)
echo "🌐 Deploying ingress configuration..."
kubectl apply -f deployments/ingress.yml

# Wait for ingress to be ready
echo "⏳ Waiting for ingress to be ready..."
kubectl wait --namespace ingress-nginx \
    --for=condition=ready pod \
    --selector=app.kubernetes.io/component=controller \
    --timeout=300s

# 13. (Optional) Deploy debug pod
echo "🐛 Deploying debug pod..."
kubectl apply -f deployments/debug-pod.yml

# 14. Post-deployment Key Vault checks
echo "🔍 Running post-deployment Key Vault checks..."
./creation-scripts/kv-post.sh

# 15. Display deployment summary
echo ""
echo "🎉 Deployment completed successfully!"
echo ""
echo "📊 Deployment Summary:"
echo "======================"

# Get static IP
NODE_RESOURCE_GROUP=$(az aks show --name Privee --resource-group Privee --query nodeResourceGroup --output tsv)
PUBLIC_IP_ADDRESS=$(az network public-ip show --resource-group "$NODE_RESOURCE_GROUP" --name "privee-public-ip" --query ipAddress --output tsv)

echo "🌐 Static IP Address: $PUBLIC_IP_ADDRESS"
echo "🏠 Application URL: https://privee.northeurope.cloudapp.azure.com"
echo "🔐 Key Vault: Privee-KV"
echo "☸️  AKS Cluster: Privee"
echo ""
echo "📝 Next Steps:"
echo "1. Update your DNS records to point privee.northeurope.cloudapp.azure.com to: $PUBLIC_IP_ADDRESS"
echo "2. Wait for DNS propagation (may take a few minutes)"
echo "3. Verify certificate sync: kubectl get secret ingress-tls -n default"
echo "4. Test the application: curl -k https://privee.northeurope.cloudapp.azure.com"
echo ""
echo "🔍 Useful Commands:"
echo "- Check ingress status: kubectl get ingress -n default"
echo "- Check NGINX controller: kubectl get pods -n ingress-nginx"
echo "- Check application pods: kubectl get pods -n default"
echo "- View application logs: kubectl logs -f deployment/privee -n default"
echo ""
echo "✅ All resources deployed. Your application should be accessible shortly!"
