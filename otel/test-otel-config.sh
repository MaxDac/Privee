#!/bin/bash

# Test OpenTelemetry configuration across different environments
#
# This script validates that OpenTelemetry dependencies are properly
# configured and can be compiled without errors.

echo "🧪 Testing OpenTelemetry Configuration"
echo "====================================="
echo ""

# Go to project root
cd "$(dirname "$0")/.."

echo "📦 Installing dependencies..."
mix deps.get

if [ $? -ne 0 ]; then
    echo "❌ Failed to get dependencies"
    exit 1
fi

echo ""
echo "🔨 Compiling project..."
mix deps.compile

if [ $? -ne 0 ]; then
    echo "❌ Failed to compile dependencies"
    exit 1
fi

echo ""
echo "🔧 Testing OTEL configuration loading..."

# Test with OTEL disabled
echo "  Testing with OTEL_ACTIVE=false..."
OTEL_ACTIVE=false mix compile > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "  ✅ OTEL disabled configuration loads correctly"
else
    echo "  ❌ Failed to load configuration with OTEL disabled"
    exit 1
fi

# Test with OTEL enabled
echo "  Testing with OTEL_ACTIVE=true..."
OTEL_ACTIVE=true mix compile > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "  ✅ OTEL enabled configuration loads correctly"
else
    echo "  ❌ Failed to load configuration with OTEL enabled"
    exit 1
fi

echo ""
echo "🔍 Checking OpenTelemetry dependencies..."

# Check if OTEL dependencies are available
if mix deps | grep -q "opentelemetry"; then
    echo "  ✅ OpenTelemetry dependencies found:"
    mix deps | grep "opentelemetry" | head -5
else
    echo "  ❌ OpenTelemetry dependencies not found"
    exit 1
fi

echo ""
echo "📋 Testing configuration values..."

# Test OTEL disabled
echo "  Testing OTEL_ACTIVE=false configuration..."
OTEL_ACTIVE=false MIX_ENV=dev mix run -e "
exporter = Application.get_env(:opentelemetry, :traces_exporter)
processors = Application.get_env(:opentelemetry, :processors)
IO.puts(\"  Traces exporter: #{inspect(exporter)}\")
IO.puts(\"  Processors: #{inspect(processors)}\")
" 2>/dev/null

echo ""
echo "  Testing OTEL_ACTIVE=true configuration..."
OTEL_ACTIVE=true MIX_ENV=dev mix run -e "
processors = Application.get_env(:opentelemetry, :processors)
resource = Application.get_env(:opentelemetry, :resource)
IO.puts(\"  Processors configured: #{not is_nil(processors) and processors != []}\")
IO.puts(\"  Resource configured: #{not is_nil(resource)}\")
" 2>/dev/null

echo ""
echo "📋 Usage Summary:"
echo "------------------------"
echo "🔧 To start development WITHOUT OpenTelemetry:"
echo "   mix phx.server"
echo ""
echo "🔧 To start development WITH OpenTelemetry:"
echo "   1. Start database: docker run --name privee-database -e POSTGRES_USER=postgres -e POSTGRES_PASSWORD=postgres --restart=unless-stopped -p 5432:5432 -d postgres"
echo "   2. Start observability stack: ./otel/start-otel-stack.sh"
echo "   3. Start Phoenix: OTEL_ACTIVE=true mix phx.server"
echo "   4. View traces: http://localhost:16686"
echo ""
echo "✅ All OpenTelemetry configuration tests passed!"
