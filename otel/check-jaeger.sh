#!/bin/bash

# Quick Jaeger Traces Check
# Simple script to check what traces are currently in Jaeger

echo "🔍 Checking Jaeger for existing traces..."

# Check if Jaeger is accessible
if ! curl -s http://localhost:16686 > /dev/null; then
    echo "❌ Jaeger UI is not accessible at http://localhost:16686"
    echo "🚀 Start the stack with: ./otel/start-otel-stack.sh"
    exit 1
fi

echo "✅ Jaeger UI is accessible"

# Get list of services
echo ""
echo "📋 Available services in Jaeger:"
SERVICES=$(curl -s "http://localhost:16686/api/services" | jq -r '.data[]?' 2>/dev/null || echo "No services found")
if [ "$SERVICES" = "No services found" ] || [ -z "$SERVICES" ]; then
    echo "❌ No services found in Jaeger"
    echo "💡 This means no traces have been sent yet"
else
    echo "✅ Found services:"
    echo "$SERVICES" | sed 's/^/  - /'
fi

# Check for recent traces
echo ""
echo "📋 Checking for recent traces..."
CURRENT_TIME=$(date +%s)000  # Convert to milliseconds
START_TIME=$((CURRENT_TIME - 3600000))  # 1 hour ago

if echo "$SERVICES" | grep -q "privee"; then
    echo "🔍 Checking traces for 'privee' service..."
    TRACES=$(curl -s "http://localhost:16686/api/traces?service=privee&start=${START_TIME}&end=${CURRENT_TIME}&limit=10" | jq '.data | length' 2>/dev/null || echo "0")
    if [ "$TRACES" -gt 0 ]; then
        echo "✅ Found $TRACES recent traces for 'privee' service!"
    else
        echo "⚠️  No recent traces found for 'privee' service"
    fi
else
    echo "⚠️  'privee' service not found in Jaeger"
fi

echo ""
echo "🌐 Open Jaeger UI to explore: http://localhost:16686"
echo "📊 OTEL Collector metrics: http://localhost:8889/metrics"
