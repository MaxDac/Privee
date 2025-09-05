# How to Verify Telemetry Data is Being Sent

This guide shows you exactly how to verify that metrics, traces, and logs are being pushed to your local observability stack.

## Quick Verification Commands

### 1. 🚀 Make Scripts Executable (run once)
```bash
chmod +x otel/*.sh
```

### 2. 🔍 Check Current Status
```bash
# Check what's in Jaeger right now
./otel/check-jaeger.sh

# Check OTEL Collector metrics
./otel/check-collector-metrics.sh

# Full verification (starts server, generates traces, checks everything)
./otel/verify-telemetry.sh
```

## Manual Verification Steps

### Step 1: Ensure Stack is Running
```bash
# Start the observability stack
./otel/start-otel-stack.sh

# Verify containers are up
docker compose -f otel/docker-compose.dev.yml ps
```

### Step 2: Start Phoenix with OpenTelemetry
```bash
# Start Phoenix server with OTEL enabled
OTEL_ACTIVE=true mix phx.server
```

You should see this log message confirming OTEL is working:
```
[info] Exporter :otel_exporter_otlp successfully initialized
```

### Step 3: Generate Some Traffic
In another terminal, make some HTTP requests:
```bash
# Generate traces
curl http://localhost:4000
curl http://localhost:4000/users
curl http://localhost:4000/api/health

# Or use the test script
./otel/test-traces.sh
```

### Step 4: Check for Traces in Jaeger

#### Option A: Web UI
1. Open http://localhost:16686 in your browser
2. In the "Service" dropdown, select `privee`
3. Click "Find Traces"
4. You should see traces for your HTTP requests

#### Option B: API Check
```bash
# Check services
curl http://localhost:16686/api/services | jq '.data'

# Check for recent traces
curl "http://localhost:16686/api/traces?service=privee&limit=10" | jq '.data | length'
```

### Step 5: Verify OTEL Collector is Processing Data
```bash
# Check collector internal metrics
curl http://localhost:8889/metrics | grep -E "otelcol_(receiver|exporter)_.*_spans"
```

Look for metrics like:
- `otelcol_receiver_accepted_spans` (data coming in)
- `otelcol_exporter_sent_spans` (data going to Jaeger)

## What Each Component Shows

### 🟦 Jaeger (http://localhost:16686)
- **Traces**: Individual request flows through your application
- **Services**: Your Phoenix app should appear as "privee"
- **Operations**: HTTP endpoints, database queries, etc.

### 📊 OTEL Collector Metrics (http://localhost:8889/metrics)
- **Receiver metrics**: Data coming from your Phoenix app
- **Processor metrics**: Data being processed by the collector
- **Exporter metrics**: Data being sent to Jaeger

### 🔍 What to Look For

#### In Jaeger UI:
- Service name: `privee`
- Span names like:
  - `HTTP GET /`
  - `HTTP GET /users`
  - `PriveeWeb.Endpoint`
  - Database operations (if using Ecto)

#### In OTEL Collector Metrics:
```
# These counters should be > 0 if data is flowing
otelcol_receiver_accepted_spans
otelcol_exporter_sent_spans
otelcol_receiver_accepted_metric_points
```

## Troubleshooting

### No Traces in Jaeger?
1. Check if Phoenix started with OTEL:
   ```bash
   # Should show "successfully initialized"
   OTEL_ACTIVE=true mix phx.server | grep "otel"
   ```

2. Check OTEL Collector logs:
   ```bash
   docker compose -f otel/docker-compose.dev.yml logs otel-collector
   ```

3. Verify configuration:
   ```bash
   ./otel/test-otel-config.sh
   ```

### OTEL Collector Not Receiving Data?
1. Check if Phoenix is sending to the right endpoint:
   - Development: `http://localhost:4317`
   - Check `config/dev.exs` for the correct configuration

2. Check firewall/networking:
   ```bash
   # Test if collector is reachable
   curl -v http://localhost:4317
   ```

### Phoenix Won't Start?
1. Check if another Phoenix server is running:
   ```bash
   pkill -f "mix phx.server"
   ```

2. Check if port 4000 is in use:
   ```bash
   lsof -i :4000
   ```

## Success Indicators

✅ **Everything is working when you see:**

1. **Phoenix logs**: `[info] Exporter :otel_exporter_otlp successfully initialized`
2. **Jaeger UI**: "privee" service appears in the dropdown
3. **Traces**: HTTP request traces visible in Jaeger
4. **Collector metrics**: `otelcol_receiver_accepted_spans > 0`

## Advanced Verification

### Check Specific Metrics
```bash
# Phoenix-specific metrics
curl http://localhost:8889/metrics | grep phoenix

# Database metrics (if using Ecto)
curl http://localhost:8889/metrics | grep ecto

# HTTP metrics
curl http://localhost:8889/metrics | grep http
```

### Generate Load for Testing
```bash
# Generate continuous traffic
for i in {1..50}; do 
  curl -s http://localhost:4000 > /dev/null
  sleep 0.1
done
```

Then check Jaeger for a bunch of traces!

## Summary

Your telemetry pipeline: **Phoenix App** → **OTEL Collector** → **Jaeger**

Use the verification scripts for quick checks, or follow the manual steps for detailed investigation. The key is seeing data flow through each component in the pipeline.
