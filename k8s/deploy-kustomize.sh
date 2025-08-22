#!/bin/bash

# Privee Kubernetes Deployment Script (using Kustomize)
# This script deploys the Privee application using Kustomize

set -e  # Exit on any error

echo "🚀 Starting Privee Kubernetes deployment with Kustomize..."

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl is not installed or not in PATH"
    exit 1
fi

# Check if we're connected to a cluster
if ! kubectl cluster-info &> /dev/null; then
    echo "❌ Not connected to a Kubernetes cluster"
    echo "Please configure kubectl to connect to your cluster first"
    exit 1
fi

# Get current directory (should be the k8s directory)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "📁 Deploying from: $SCRIPT_DIR"

# Deploy using Kustomize
echo "🏗️  Applying all resources with Kustomize..."
if kubectl apply -k "$SCRIPT_DIR"; then
    echo "✅ All resources applied successfully"
else
    echo "❌ Failed to apply resources"
    exit 1
fi

echo ""
echo "🎉 Deployment completed successfully!"
echo ""

# Wait for deployment to be ready
echo "⏳ Waiting for deployment to be ready..."
if kubectl rollout status deployment/privee --timeout=300s; then
    echo "✅ Deployment is ready!"
else
    echo "⚠️  Deployment is taking longer than expected"
fi

echo ""
echo "📋 Current status:"
kubectl get pods -l app=privee
echo ""
kubectl get services
echo ""

echo "🌍 Application access:"
echo "- LoadBalancer service: kubectl get service privee-loadbalancer"
echo "- Port forward for local access: kubectl port-forward deployment/privee 4000:4000"
echo "- View logs: kubectl logs -l app=privee --tail=50"

echo ""
echo "✨ Privee deployment complete!"
