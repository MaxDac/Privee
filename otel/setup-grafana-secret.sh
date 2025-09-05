#!/bin/bash

# Setup Grafana OTEL secret for Kubernetes deployment
#
# This script creates a Kubernetes secret containing the Grafana Cloud
# OTEL token required for production telemetry export.

echo "📝 Setting up Grafana OpenTelemetry secret for Kubernetes..."
echo ""

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "❌ Error: kubectl is not installed or not in PATH"
    exit 1
fi

# Check if we can connect to a Kubernetes cluster
if ! kubectl cluster-info &> /dev/null; then
    echo "❌ Error: Cannot connect to Kubernetes cluster"
    echo "   Make sure you're connected to your AKS cluster"
    exit 1
fi

echo "Please enter your Grafana OTEL token:"
read -s token

if [ -z "$token" ]; then
    echo "❌ Error: Token cannot be empty"
    exit 1
fi

# Create the secret
encoded_token=$(echo -n "$token" | base64)
kubectl create secret generic grafana-otel-secret \
    --from-literal=GRAFANA_OTEL_TOKEN="$encoded_token" \
    --dry-run=client -o yaml | kubectl apply -f -

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Grafana OTEL secret created successfully!"
    echo ""
    echo "🔍 You can verify the secret with:"
    echo "  kubectl get secret grafana-otel-secret"
else
    echo "❌ Failed to create Grafana OTEL secret"
    exit 1
fi
