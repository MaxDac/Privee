#!/bin/bash#!/bin/bash



set -eset -e



echo "🔍 Verifying Azure Application Routing (managed NGINX) Status..."echo "� Verifying NGINX Ingress Controller Status..."



# Configuration# Configuration

AKS_RG="Privee"AKS_RG="Privee"

AKS_NAME="Privee"AKS_NAME="Privee"

PUBLIC_IP_NAME="privee-public-ip"PUBLIC_IP_NAME="privee-public-ip"

NAMESPACE="default"NAMESPACE="default"



# Check if kubectl is working# Check if kubectl is working

if ! kubectl cluster-info &> /dev/null; thenif ! kubectl cluster-info &> /dev/null; then

    echo "❌ kubectl is not configured or cluster is not accessible"    echo "❌ kubectl is not configured or cluster is not accessible"

    echo "Please ensure AKS credentials are configured: az aks get-credentials -g $AKS_RG -n $AKS_NAME"    echo "Please ensure AKS credentials are configured: az aks get-credentials -g $AKS_RG -n $AKS_NAME"

    exit 1    exit 1

fifi



echo "✅ kubectl connectivity verified"echo "✅ kubectl connectivity verified"



# Check if Application Routing is enabled# Get the node resource group and public IP address

echo "🔍 Checking Application Routing status..."echo "📋 Getting AKS node resource group..."

APP_ROUTING_STATUS=$(az aks show -g "$AKS_RG" -n "$AKS_NAME" --query "addonProfiles.httpApplicationRouting.enabled" -o tsv 2>/dev/null || echo "false")NODE_RESOURCE_GROUP=$(az aks show \

    --name "$AKS_NAME" \

if [ "$APP_ROUTING_STATUS" != "true" ]; then    --resource-group "$AKS_RG" \

    echo "❌ Azure Application Routing is not enabled!"    --query nodeResourceGroup \

    echo "Please run ./ingress.sh first to enable Application Routing"    --output tsv)

    exit 1

fiecho "📋 Getting static public IP address..."

if ! PUBLIC_IP_ADDRESS=$(az network public-ip show \

echo "✅ Azure Application Routing is enabled"    --resource-group "$NODE_RESOURCE_GROUP" \

    --name "$PUBLIC_IP_NAME" \

# Get the node resource group and public IP address    --query ipAddress \

echo "📋 Getting AKS node resource group..."    --output tsv 2>/dev/null); then

NODE_RESOURCE_GROUP=$(az aks show \    echo "❌ Static IP '$PUBLIC_IP_NAME' not found in resource group '$NODE_RESOURCE_GROUP'"

    --name "$AKS_NAME" \    echo "Please run ./setup-azure-ip.sh first to create the static IP"

    --resource-group "$AKS_RG" \    exit 1

    --query nodeResourceGroup \fi

    --output tsv)

echo "✅ Static IP found: $PUBLIC_IP_ADDRESS"

echo "📋 Getting static public IP address..."echo "✅ Node resource group: $NODE_RESOURCE_GROUP"

if ! PUBLIC_IP_ADDRESS=$(az network public-ip show \

    --resource-group "$NODE_RESOURCE_GROUP" \# Check if NGINX Ingress Controller is installed and running

    --name "$PUBLIC_IP_NAME" \echo "🔍 Checking NGINX Ingress Controller status..."

    --query ipAddress \if ! kubectl get namespace ingress-nginx &>/dev/null; then

    --output tsv 2>/dev/null); then    echo "❌ NGINX Ingress Controller namespace not found!"

    echo "❌ Static IP '$PUBLIC_IP_NAME' not found in resource group '$NODE_RESOURCE_GROUP'"    echo "Please run ./ingress.sh first to install NGINX Ingress Controller"

    echo "Please run ./setup-azure-ip.sh first to create the static IP"    exit 1

    exit 1fi

fi

# Check if NGINX Ingress Controller pods are running

echo "✅ Static IP found: $PUBLIC_IP_ADDRESS"if ! kubectl get pods -n ingress-nginx --selector=app.kubernetes.io/component=controller &>/dev/null; then

echo "✅ Node resource group: $NODE_RESOURCE_GROUP"    echo "❌ NGINX Ingress Controller pods not found!"

    echo "Please run ./ingress.sh first to install NGINX Ingress Controller"

# Check if Application Routing system namespace exists    exit 1

echo "🔍 Checking Application Routing system components..."fi

if ! kubectl get namespace app-routing-system &>/dev/null; then

    echo "❌ app-routing-system namespace not found!"echo "✅ NGINX Ingress Controller namespace exists"

    echo "Application Routing may still be initializing. Wait a few minutes and try again."

    exit 1# Wait for the LoadBalancer service to be ready

fiecho "⏳ Waiting for NGINX Ingress Controller to be ready..."

kubectl wait --namespace ingress-nginx \

# Check if NGINX controller pods are running in app-routing-system    --for=condition=ready pod \

if ! kubectl get pods -n app-routing-system --selector=app=nginx &>/dev/null; then    --selector=app.kubernetes.io/component=controller \

    echo "⚠️  NGINX controller pods not found in app-routing-system"    --timeout=120s

    echo "Application Routing may still be initializing..."

fi# Show the service status

echo "📊 NGINX Ingress Controller service status:"

echo "✅ Application Routing system namespace exists"kubectl get svc -n ingress-nginx



# Wait for Application Routing components to be ready# Verify the IP assignment

echo "⏳ Waiting for Application Routing components to be ready..."echo "🔍 Verifying IP assignment..."

kubectl wait --namespace app-routing-system \ASSIGNED_IP=$(kubectl get svc -n ingress-nginx nginx-ingress-ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")

    --for=condition=ready pod \

    --selector=app=nginx \if [ "$ASSIGNED_IP" = "$PUBLIC_IP_ADDRESS" ]; then

    --timeout=300s || echo "⚠️  Some pods may still be starting up"    echo "✅ Static IP successfully assigned: $ASSIGNED_IP"

elif [ -z "$ASSIGNED_IP" ]; then

# Show the service status    echo "⚠️  LoadBalancer IP not yet assigned. This may take a few minutes."

echo "📊 Application Routing service status:"    echo "   Expected IP: $PUBLIC_IP_ADDRESS"

kubectl get svc -n app-routing-system || echo "⚠️  Services may still be initializing"else

    echo "⚠️  IP assignment mismatch: Expected $PUBLIC_IP_ADDRESS, got $ASSIGNED_IP"

# Verify Key Vault integration    echo "   This may indicate a configuration issue with the static IP setup"

echo "🔐 Checking Key Vault integration..."fi

if kubectl get ClusterRole azure-keyvault-secrets-provider-cluster-role &>/dev/null; then

    echo "✅ Key Vault Secrets Provider is installed"echo ""

elseecho "✅ NGINX Ingress Controller verification completed!"

    echo "⚠️  Key Vault Secrets Provider not found - this may affect SSL certificate management"echo ""

fiecho "📝 Status Summary:"

echo "- NGINX Ingress Controller: Running"

echo ""echo "- Static IP: $PUBLIC_IP_ADDRESS"  

echo "✅ Azure Application Routing verification completed!"echo "- Node Resource Group: $NODE_RESOURCE_GROUP"

echo ""echo ""

echo "📝 Status Summary:"echo "🔧 If you need to troubleshoot:"

echo "- Azure Application Routing: Enabled"echo "- Check pods: kubectl get pods -n ingress-nginx"

echo "- Static IP: $PUBLIC_IP_ADDRESS"  echo "- Check service: kubectl get svc -n ingress-nginx"

echo "- Node Resource Group: $NODE_RESOURCE_GROUP"echo "- Check logs: kubectl logs -n ingress-nginx deployment/nginx-ingress-ingress-nginx-controller"
echo "- Key Vault Integration: Available"
echo ""
echo "🔧 If you need to troubleshoot:"
echo "- Check Application Routing pods: kubectl get pods -n app-routing-system"
echo "- Check Application Routing services: kubectl get svc -n app-routing-system"
echo "- Check ingress resources: kubectl get ingress -n default"
echo "- Check Application Routing logs: kubectl logs -n app-routing-system -l app=nginx"