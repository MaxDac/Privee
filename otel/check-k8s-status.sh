#!/bin/bash

# Check OpenTelemetry status in Kubernetes
#
# This script checks the status of OpenTelemetry-related resources
# in the Kubernetes cluster.

echo "📊 OpenTelemetry Kubernetes Status Check"
echo "========================================"

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "❌ Error: kubectl is not installed or not in PATH"
    exit 1
fi

# Check if we can connect to a Kubernetes cluster
if ! kubectl cluster-info &> /dev/null; then
    echo "❌ Error: Cannot connect to Kubernetes cluster"
    exit 1
fi

echo ""
echo "🔐 Checking Secrets:"
echo "-------------------"
if kubectl get secret grafana-otel-secret &> /dev/null; then
    echo "✅ grafana-otel-secret exists"
    kubectl get secret grafana-otel-secret -o jsonpath='{.metadata.creationTimestamp}' | xargs -I {} echo "   Created: {}"
else
    echo "❌ grafana-otel-secret not found"
    echo "   Run: ./otel/setup-grafana-secret.sh"
fi

echo ""
echo "📡 Checking Network Policies:"
echo "----------------------------"
if kubectl get networkpolicy privee-grafana-egress &> /dev/null; then
    echo "✅ privee-grafana-egress network policy exists"
else
    echo "❌ privee-grafana-egress network policy not found"
    echo "   Make sure to apply: .azure/k8s/network-policy.yml"
fi

echo ""
echo "🚀 Checking Pod Environment:"
echo "---------------------------"
pods=$(kubectl get pods -l app=privee -o name 2>/dev/null)
if [ -n "$pods" ]; then
    echo "✅ Found Privee pods:"
    kubectl get pods -l app=privee
    echo ""
    echo "🔧 OTEL Environment Variables:"
    kubectl get pods -l app=privee -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{range .spec.containers[0].env[?(@.name=="OTEL_SERVICE_NAME")]}{.name}: {.value}{"\n"}{end}{"\n"}{end}' 2>/dev/null || echo "   No OTEL_SERVICE_NAME found"
else
    echo "❌ No pods found with label app=privee"
    echo "   Make sure your application is deployed"
fi

echo ""
echo "📈 Recent Pod Logs (last 10 lines):"
echo "-----------------------------------"
if [ -n "$pods" ]; then
    kubectl logs -l app=privee --tail=10 2>/dev/null || echo "❌ Unable to fetch logs"
else
    echo "❌ No pods available for log checking"
fi
