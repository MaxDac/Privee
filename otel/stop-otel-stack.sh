#!/bin/bash

# Stop OpenTelemetry observability stack
#
# This script stops and removes the Jaeger and OTEL Collector containers.

echo "🛑 Stopping OpenTelemetry observability stack..."

# Stop the observability stack
docker compose -f "$(dirname "$0")/docker-compose.dev.yml" down

if [ $? -eq 0 ]; then
    echo "✅ OpenTelemetry stack stopped successfully!"
else
    echo "❌ Failed to stop OpenTelemetry stack"
    exit 1
fi
