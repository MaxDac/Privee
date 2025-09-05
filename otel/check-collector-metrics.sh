#!/bin/bash

# OTEL Collector Metrics Check
# Check OTEL Collector internal metrics to see if it's receiving/processing data

echo "📊 OTEL Collector Metrics Analysis"
echo "=================================="

if ! curl -s http://localhost:8889/metrics > /dev/null; then
    echo "❌ OTEL Collector metrics endpoint not accessible"
    echo "🚀 Start the stack with: ./otel/start-otel-stack.sh"
    exit 1
fi

echo "✅ OTEL Collector metrics endpoint is accessible"
echo ""

# Fetch metrics
METRICS=$(curl -s http://localhost:8889/metrics)

# Check receiver metrics
echo "📥 RECEIVER METRICS (data coming in):"
echo "$METRICS" | grep -E "otelcol_receiver.*_accepted_" | tail -5
if [ $(echo "$METRICS" | grep -E "otelcol_receiver.*_accepted_" | wc -l) -eq 0 ]; then
    echo "  ⚠️  No receiver metrics found - no data being received"
else
    echo "  ✅ Receiver is accepting data"
fi

echo ""

# Check processor metrics  
echo "⚙️  PROCESSOR METRICS (data being processed):"
echo "$METRICS" | grep -E "otelcol_processor.*_accepted_" | tail -5
if [ $(echo "$METRICS" | grep -E "otelcol_processor.*_accepted_" | wc -l) -eq 0 ]; then
    echo "  ⚠️  No processor metrics found"
else
    echo "  ✅ Processor is handling data"
fi

echo ""

# Check exporter metrics
echo "📤 EXPORTER METRICS (data being sent out):"
echo "$METRICS" | grep -E "otelcol_exporter.*_sent_" | tail -5
if [ $(echo "$METRICS" | grep -E "otelcol_exporter.*_sent_" | wc -l) -eq 0 ]; then
    echo "  ⚠️  No exporter metrics found"
else
    echo "  ✅ Exporter is sending data"
fi

echo ""

# Summary of data flow
echo "📈 DATA FLOW SUMMARY:"
SPANS_RECEIVED=$(echo "$METRICS" | grep "otelcol_receiver_accepted_spans" | tail -1 | awk '{print $2}' || echo "0")
SPANS_EXPORTED=$(echo "$METRICS" | grep "otelcol_exporter_sent_spans" | tail -1 | awk '{print $2}' || echo "0")

echo "  Spans received: ${SPANS_RECEIVED:-0}"
echo "  Spans exported: ${SPANS_EXPORTED:-0}"

if [ "${SPANS_RECEIVED:-0}" -gt 0 ]; then
    echo "  ✅ OTEL Collector is receiving trace data"
else
    echo "  ❌ OTEL Collector is not receiving trace data"
    echo "     💡 Make sure Phoenix is running with OTEL_ACTIVE=true"
fi

if [ "${SPANS_EXPORTED:-0}" -gt 0 ]; then
    echo "  ✅ OTEL Collector is exporting trace data to Jaeger"
else
    echo "  ⚠️  OTEL Collector is not exporting trace data"
fi

echo ""
echo "🔗 Full metrics available at: http://localhost:8889/metrics"
