#!/bin/bash

# Fix OpenTelemetry Dependencies Script
# This script cleans up and reinstalls the correct OpenTelemetry versions

set -e

echo "🔧 Fixing OpenTelemetry Dependencies..."

# Stop any running servers
echo "🛑 Stopping any running servers..."
pkill -f "mix phx.server" 2>/dev/null || true
pkill -f "iex.*mix" 2>/dev/null || true

# Clean dependencies
echo "🧹 Cleaning dependencies..."
mix deps.clean --all

# Get dependencies
echo "📦 Fetching updated dependencies..."
mix deps.get

# Compile
echo "🔨 Compiling with new dependencies..."
mix compile

# Test configuration
echo "🧪 Testing OTEL configuration..."
timeout 5s bash -c "OTEL_ACTIVE=true mix compile" || echo "Compilation completed"

if OTEL_ACTIVE=true mix compile 2>&1 | grep -q "error"; then
    echo "❌ Configuration has errors"
    exit 1
else
    echo "✅ Configuration compiles successfully"
fi

echo ""
echo "✅ OpenTelemetry dependencies fixed!"
echo "🚀 You can now test with: OTEL_ACTIVE=true mix phx.server"
