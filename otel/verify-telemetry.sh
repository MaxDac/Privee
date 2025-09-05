#!/bin/bash

# OpenTelemetry Complete Stack Verification Script
# This script helps verify that metrics, traces, and logs are being sent to your complete observability stack

set -e

echo "🔍 Complete Observability Stack Verification"
echo "============================================="

# Check if observability stack is running
echo ""
echo "📋 Step 1: Checking observability stack status..."
if ! docker compose -f otel/docker-compose.dev.yml ps | grep -q "Up"; then
    echo "❌ Observability stack is not running!"
    echo "🚀 Start it with: ./otel/start-otel-stack.sh"
    exit 1
else
    echo "✅ Observability stack is running"
fi

# Function to check service health
check_service() {
    local name=$1
    local url=$2
    local description=$3
    
    if curl -s "$url" > /dev/null 2>&1; then
        echo "✅ $name: $description"
        return 0
    else
        echo "❌ $name: Not accessible at $url"
        return 1
    fi
}

# Check all services
echo ""
echo "📋 Step 2: Checking all service endpoints..."
check_service "Jaeger" "http://localhost:16686" "Traces UI accessible"
check_service "Grafana" "http://localhost:3000" "Dashboards accessible (admin/admin)"
check_service "Prometheus" "http://localhost:9090" "Metrics storage accessible"
check_service "Loki" "http://localhost:3100/ready" "Log aggregation ready"
check_service "OTEL Collector" "http://localhost:8889/metrics" "Collector metrics available"

# Start Phoenix server in background and generate traces
echo ""
echo "📋 Step 3: Generating test data..."
echo "🚀 Starting Phoenix server with OTEL..."

# Kill any existing Phoenix processes
pkill -f "mix phx.server" 2>/dev/null || true
sleep 2

# Start Phoenix server in background
OTEL_ACTIVE=true mix phx.server &
SERVER_PID=$!

# Wait for server to start
echo "⏳ Waiting for server to start..."
sleep 8

# Check if server is responding
if curl -s -o /dev/null -w "%{http_code}" http://localhost:4000 | grep -q "200"; then
    echo "✅ Phoenix server is running"
    
    # Generate traces by making requests
    echo "📊 Generating traces, metrics, and logs..."
    for i in {1..5}; do
        curl -s http://localhost:4000 > /dev/null || true
        curl -s http://localhost:4000/users > /dev/null 2>&1 || true
        sleep 1
    done
    echo "✅ Test requests completed"
    
else
    echo "❌ Phoenix server is not responding"
fi

# Stop Phoenix server
echo "🛑 Stopping Phoenix server..."
kill $SERVER_PID 2>/dev/null || true
wait $SERVER_PID 2>/dev/null || true

# Check for traces in Jaeger
echo ""
echo "📋 Step 4: Checking for traces in Jaeger..."
sleep 3

JAEGER_SERVICES=$(curl -s "http://localhost:16686/api/services" | jq -r '.data[]' 2>/dev/null || echo "")
if echo "$JAEGER_SERVICES" | grep -q "privee"; then
    echo "✅ Found traces for 'privee' service in Jaeger!"
    echo "🔍 Services found: $JAEGER_SERVICES"
else
    echo "⚠️  No traces found yet (may take a few moments to appear)"
    echo "🔍 Available services: $JAEGER_SERVICES"
fi

# Check Prometheus for metrics
echo ""
echo "📋 Step 5: Checking Prometheus metrics..."
PROMETHEUS_METRICS=$(curl -s "http://localhost:9090/api/v1/query?query=otelcol_receiver_accepted_spans_total" | jq -r '.data.result | length' 2>/dev/null || echo "0")
if [ "$PROMETHEUS_METRICS" -gt 0 ]; then
    echo "✅ Found OTEL metrics in Prometheus!"
else
    echo "⚠️  No OTEL metrics found in Prometheus yet"
fi

# Check Grafana datasources
echo ""
echo "📋 Step 6: Checking Grafana datasources..."
GRAFANA_HEALTH=$(curl -s "http://admin:admin@localhost:3000/api/health" | jq -r '.database' 2>/dev/null || echo "unknown")
if [ "$GRAFANA_HEALTH" = "ok" ]; then
    echo "✅ Grafana is healthy and ready!"
else
    echo "⚠️  Grafana database status: $GRAFANA_HEALTH"
fi

echo ""
echo "🎯 Manual Verification Steps:"
echo "=============================="
echo ""
echo "🔍 1. **Jaeger (Traces)**: http://localhost:16686"
echo "   - Select 'privee' from Service dropdown"
echo "   - Click 'Find Traces' to see HTTP request traces"
echo "   - Look for Phoenix endpoint traces"
echo ""
echo "� 2. **Grafana (Unified Dashboard)**: http://localhost:3000 (admin/admin)"
echo "   - Check 'Phoenix OpenTelemetry Dashboard'"
echo "   - Explore → Select Jaeger to see traces"
echo "   - Explore → Select Loki to see logs"
echo ""
echo "📊 3. **Prometheus (Raw Metrics)**: http://localhost:9090"
echo "   - Search for 'otelcol_receiver_accepted_spans_total'"
echo "   - Check other otelcol_* metrics"
echo ""
echo "📝 4. **Loki (Logs)**: Accessible via Grafana or direct API"
echo "   - Via Grafana: Explore → Loki"
echo "   - Direct API: curl \"http://localhost:3100/loki/api/v1/query?query={job=\\\"phoenix\\\"}\""
echo ""
echo "🔧 5. **Generate More Data**:"
echo "   - Start: OTEL_ACTIVE=true mix phx.server"
echo "   - Generate: curl http://localhost:4000"
echo "   - Or use: ./otel/test-traces.sh"
echo ""
echo "🎉 Complete Observability Stack Verification Complete!"
echo ""
echo "📋 **Summary of Your Stack:**"
echo "├── 🔍 Traces: Jaeger → http://localhost:16686"
echo "├── 📊 Metrics: Prometheus → http://localhost:9090"  
echo "├── 📝 Logs: Loki → accessible via Grafana"
echo "├── 📈 Dashboards: Grafana → http://localhost:3000"
echo "└── ⚙️  Processing: OTEL Collector → localhost:4317/4318"
