#!/bin/bash

# Script to create Grafana OpenTelemetry secret for Kubernetes
# This script helps with setting up the required secret for OpenTelemetry export to Grafana Cloud

set -e

echo "🔐 Grafana OpenTelemetry Secret Setup"
echo "====================================="
echo ""

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl is not installed or not in PATH"
    exit 1
fi

# Check if we're connected to a cluster
if ! kubectl cluster-info &> /dev/null; then
    echo "❌ Not connected to a Kubernetes cluster"
    echo "Please run 'kubectl config current-context' to verify your connection"
    exit 1
fi

echo "📋 Instructions:"
echo "1. Go to your Grafana Cloud stack"
echo "2. Navigate to 'Connections' → 'Add new connection' → 'OpenTelemetry'"
echo "3. Copy your instance ID and create an API token"
echo "4. Format: instanceId:token"
echo ""

# Prompt for token
echo "🔑 Please enter your Grafana OTEL token (format: instanceId:token):"
read -s grafana_token

if [ -z "$grafana_token" ]; then
    echo "❌ Token cannot be empty"
    exit 1
fi

# Encode the token
encoded_token=$(echo -n "$grafana_token" | base64)

# Create the secret
echo ""
echo "🚀 Creating Kubernetes secret..."

kubectl create secret generic grafana-otel-secret \
    --from-literal=GRAFANA_OTEL_TOKEN="$encoded_token" \
    --dry-run=client -o yaml | kubectl apply -f -

if [ $? -eq 0 ]; then
    echo "✅ Secret 'grafana-otel-secret' created successfully"
    echo ""
    echo "📊 You can now deploy your application with OpenTelemetry enabled:"
    echo "   cd .azure/k8s && ./deploy.sh"
    echo ""
    echo "🔍 To verify the secret was created:"
    echo "   kubectl get secret grafana-otel-secret"
else
    echo "❌ Failed to create secret"
    exit 1
fi
