#!/bin/bash

# Start OpenTelemetry observability stack for local development
#
# This script starts Jaeger, OTEL Collector, Prometheus, Grafana, and Loki using Docker Compose.
# The external PostgreSQL database should be started separately using
# the command provided in the README.md file.

echo "🚀 Starting Complete Observability Stack..."
echo ""

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo "❌ Error: Docker is not running. Please start Docker first."
    exit 1
fi

# Start the observability stack
docker compose -f "$(dirname "$0")/docker-compose.dev.yml" up -d

if [ $? -eq 0 ]; then
    echo ""
    echo "⏳ Waiting for services to be ready..."
    sleep 15
    
    echo ""
    echo "✅ Complete Observability Stack started successfully!"
    echo ""
    echo "📊 Available services:"
    echo "  🔍 Jaeger (Traces):     http://localhost:16686"
    echo "  📈 Grafana (Dashboards): http://localhost:3000 (admin/admin)" 
    echo "  📊 Prometheus (Metrics): http://localhost:9090"
    echo "  📝 Loki (Logs):         http://localhost:3100"
    echo "  ⚙️  OTEL Collector:     http://localhost:4317 (gRPC) / http://localhost:4318 (HTTP)"
    echo "  📈 Collector Metrics:   http://localhost:8889/metrics"
    echo ""
    echo "🔗 Data Flow:"
    echo "  Phoenix → OTEL Collector → Jaeger (traces) + Prometheus (metrics) + Loki (logs) → Grafana"
    echo ""
    echo "🔧 To start your Phoenix app with OpenTelemetry:"
    echo "  OTEL_ACTIVE=true mix phx.server"
    echo ""
    echo "💡 Don't forget to start PostgreSQL database first:"
    echo "  docker run --name privee-database -e POSTGRES_USER=postgres -e POSTGRES_PASSWORD=postgres --restart=unless-stopped -p 5432:5432 -d postgres"
else
    echo "❌ Failed to start observability stack"
    exit 1
fi
