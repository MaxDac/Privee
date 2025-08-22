#!/bin/bash

# Privee Kubernetes Deployment Script
# This script deploys the Privee application to Kubernetes in the recommended order

set -e  # Exit on any error

echo "🚀 Starting Privee Kubernetes deployment..."

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

# Step 1: Apply secrets first (dependencies)
echo "🔐 1/4 Applying secrets..."
if kubectl apply -f "$SCRIPT_DIR/secrets.yml"; then
    echo "✅ Secrets applied successfully"
else
    echo "❌ Failed to apply secrets"
    exit 1
fi

# Step 2: Apply deployment (main application)
echo "🏗️  2/4 Applying deployment..."
if kubectl apply -f "$SCRIPT_DIR/deployment.yml"; then
    echo "✅ Deployment applied successfully"
else
    echo "❌ Failed to apply deployment"
    exit 1
fi

# Step 3: Apply services (networking)
echo "🌐 3/4 Applying services..."
if kubectl apply -f "$SCRIPT_DIR/services-best-practice.yml"; then
    echo "✅ Services applied successfully"
else
    echo "❌ Failed to apply services"
    exit 1
fi

# Step 4: Apply debug pod (optional)
echo "🔍 4/4 Applying debug pod..."
if kubectl apply -f "$SCRIPT_DIR/debug-pod.yml"; then
    echo "✅ Debug pod applied successfully"
else
    echo "❌ Failed to apply debug pod"
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

# Show how to access the application
echo "🌍 Application access:"
echo "- LoadBalancer service: kubectl get service privee-loadbalancer"
echo "- Port forward for local access: kubectl port-forward deployment/privee 4000:4000"
echo "- View logs: kubectl logs -l app=privee --tail=50"

echo ""
echo "✨ Privee deployment complete!"
