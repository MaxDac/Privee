#!/bin/bash

# Test OpenTelemetry traces by making requests to the Phoenix application
# This script starts the server, makes test requests, and shows traces in Jaeger

set -e

echo "🚀 Starting Phoenix server with OpenTelemetry..."
OTEL_ACTIVE=true mix phx.server &
SERVER_PID=$!

# Wait for server to start
echo "⏳ Waiting for server to start..."
sleep 5

# Test if server is responding
echo "🧪 Testing server availability..."
if curl -s http://localhost:4000 > /dev/null; then
    echo "✅ Server is running!"
    
    # Make some test requests to generate traces
    echo "📊 Generating traces..."
    curl -s http://localhost:4000 > /dev/null
    curl -s http://localhost:4000/users > /dev/null || true
    curl -s http://localhost:4000/api/health > /dev/null || true
    
    echo "✅ Test requests completed!"
    echo "🔍 Check traces at: http://localhost:16686 (Jaeger UI)"
    echo "📊 Check metrics at: http://localhost:8889/metrics (OTEL Collector)"
    
else
    echo "❌ Server is not responding"
fi

# Stop the server
echo "🛑 Stopping Phoenix server..."
kill $SERVER_PID 2>/dev/null || true
wait $SERVER_PID 2>/dev/null || true

echo "✅ Test completed!"
