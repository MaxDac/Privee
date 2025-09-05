# Complete Local Observability Stack Endpoints

## 📊 **Available Services After Running `./otel/start-otel-stack.sh`**

### 🔍 **Jaeger - Distributed Tracing**
- **URL**: http://localhost:16686
- **Purpose**: View distributed traces from your Phoenix application
- **What to expect**: 
  - Service map showing request flows
  - Individual trace details with timing
  - HTTP request traces from Phoenix
  - Database query traces (via Ecto)

### 📈 **Grafana - Unified Observability Dashboard**
- **URL**: http://localhost:3000
- **Login**: admin / admin
- **Purpose**: Unified dashboard for metrics, logs, and traces
- **Pre-configured with**:
  - Prometheus datasource (metrics)
  - Jaeger datasource (traces)
  - Loki datasource (logs)
  - Phoenix OpenTelemetry dashboard

### 📊 **Prometheus - Metrics Storage & Querying**
- **URL**: http://localhost:9090
- **Purpose**: Time-series metrics database
- **What to expect**:
  - OTEL Collector internal metrics
  - Phoenix application metrics (when available)
  - Infrastructure metrics

### 📝 **Loki - Log Aggregation**
- **URL**: http://localhost:3100
- **Purpose**: Centralized log storage and querying
- **API Endpoints**:
  - Health: http://localhost:3100/ready
  - Push API: http://localhost:3100/loki/api/v1/push
  - Query API: http://localhost:3100/loki/api/v1/query

### ⚙️ **OTEL Collector - Telemetry Data Processing**
- **gRPC Receiver**: localhost:4317 (Phoenix app sends data here)
- **HTTP Receiver**: localhost:4318 (Alternative endpoint)
- **Internal Metrics**: http://localhost:8889/metrics
- **Purpose**: Receives telemetry from Phoenix, processes and routes to backends

## 🔗 **Data Flow Architecture**

```
Phoenix App (OTEL_ACTIVE=true)
    ↓ (sends traces, metrics, logs)
OTEL Collector (localhost:4317)
    ↓ (routes data to)
    ├── Jaeger (traces)
    ├── Prometheus (metrics)  
    └── Loki (logs)
            ↓ (visualized in)
        Grafana Dashboard
```

## 🎯 **How to Verify Each Component**

### 1. **Traces in Jaeger**
```bash
# Start Phoenix with OTEL
OTEL_ACTIVE=true mix phx.server

# Make requests to generate traces
curl http://localhost:4000

# Check Jaeger UI
open http://localhost:16686
# Look for "privee" service in the dropdown
```

### 2. **Metrics in Prometheus**
```bash
# Check if OTEL Collector is sending metrics
curl http://localhost:9090/api/v1/query?query=otelcol_receiver_accepted_spans_total

# In Prometheus UI, search for:
# - otelcol_receiver_* (data coming in)
# - otelcol_exporter_* (data going out)
```

### 3. **Logs in Loki** 
```bash
# Check Loki health
curl http://localhost:3100/ready

# Query logs via API
curl "http://localhost:3100/loki/api/v1/query?query={job=\"phoenix\"}"
```

### 4. **Unified View in Grafana**
```bash
# Open Grafana
open http://localhost:3000
# Login: admin/admin

# Check datasources (should show green):
# - Prometheus ✅
# - Jaeger ✅  
# - Loki ✅

# View Phoenix dashboard:
# Navigate to "Dashboards" → "Phoenix OpenTelemetry Dashboard"
```

## 🚀 **Quick Start Workflow**

1. **Start the observability stack**:
   ```bash
   ./otel/start-otel-stack.sh
   ```

2. **Wait for all services** (takes ~15 seconds)

3. **Start Phoenix with OTEL**:
   ```bash
   OTEL_ACTIVE=true mix phx.server
   ```

4. **Generate test traffic**:
   ```bash
   ./otel/test-traces.sh
   # or manually:
   curl http://localhost:4000
   ```

5. **Verify in each UI**:
   - **Traces**: http://localhost:16686 → Select "privee" service
   - **Metrics**: http://localhost:3000 → Phoenix dashboard
   - **Logs**: http://localhost:3000 → Explore → Loki

## 🔧 **Troubleshooting Endpoints**

### Check Service Health
```bash
# All services status
docker compose -f otel/docker-compose.dev.yml ps

# Individual health checks
curl -s http://localhost:16686 > /dev/null && echo "Jaeger ✅" || echo "Jaeger ❌"
curl -s http://localhost:3000 > /dev/null && echo "Grafana ✅" || echo "Grafana ❌"  
curl -s http://localhost:9090 > /dev/null && echo "Prometheus ✅" || echo "Prometheus ❌"
curl -s http://localhost:3100/ready > /dev/null && echo "Loki ✅" || echo "Loki ❌"
curl -s http://localhost:8889/metrics > /dev/null && echo "OTEL Collector ✅" || echo "OTEL Collector ❌"
```

### Automated Verification
```bash
# Use the verification scripts
./otel/verify-telemetry.sh      # Complete end-to-end test
./otel/check-jaeger.sh          # Just check Jaeger traces
./otel/check-collector-metrics.sh  # Just check OTEL Collector
```

## 📋 **Port Summary**

| Service | Port | Purpose |
|---------|------|---------|
| Jaeger UI | 16686 | Trace visualization |
| Grafana | 3000 | Unified dashboards |
| Prometheus | 9090 | Metrics storage & query |
| Loki | 3100 | Log aggregation API |
| OTEL gRPC | 4317 | Receive telemetry from Phoenix |
| OTEL HTTP | 4318 | Alternative telemetry endpoint |
| OTEL Metrics | 8889 | Collector internal metrics |

This complete stack gives you **full observability** with traces, metrics, and logs all flowing from your Phoenix application!
