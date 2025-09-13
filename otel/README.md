# OpenTelemetry Implementation Summary

## Overview
This document summarizes the complete OpenTelemetry instrumentation implementation for the Privee application, following the project's conventions and requirements.

## Features Implemented
- ✅ **Conditional Activation**: Controlled by `OTEL_ACTIVE` environment variable
- ✅ **External Database**: Uses existing PostgreSQL setup from README.md
- ✅ **Shell Scripts**: Replaces Makefiles with executable scripts
- ✅ **Complete Instrumentation**: Phoenix, Bandit, Ecto, and custom metrics
- ✅ **Local Development Stack**: Jaeger + OTEL Collector for testing
- ✅ **Production Ready**: Grafana Cloud integration support

## Environment Variable Control

### Activation
```bash
# Enable OpenTelemetry instrumentation
export OTEL_ACTIVE=true
mix phx.server

# Disable OpenTelemetry instrumentation (default)
export OTEL_ACTIVE=false
# or simply:
mix phx.server
```

## Scripts in `otel/` Folder

### 1. `start-otel-stack.sh`
Starts complete local observability stack for development:
```bash
./otel/start-otel-stack.sh
```
**Starts all services:**
- **Jaeger UI**: http://localhost:16686 (trace visualization)
- **Grafana**: http://localhost:3000 (unified dashboards - admin/admin)
- **Prometheus**: http://localhost:9090 (metrics storage)
- **Loki**: http://localhost:3100 (log aggregation)
- **OTEL Collector**: localhost:4317 (gRPC), localhost:4318 (HTTP)
- **Collector Metrics**: http://localhost:8889/metrics

### 2. `stop-otel-stack.sh`
Stops the complete local observability stack:
```bash
./otel/stop-otel-stack.sh
```

### 3. `verify-telemetry.sh`
Comprehensive verification of the complete observability stack:
```bash
./otel/verify-telemetry.sh
```

### 4. `check-jaeger.sh`
Quick check for traces in Jaeger:
```bash
./otel/check-jaeger.sh
```

### 5. `check-collector-metrics.sh`
Verify OTEL Collector metrics and data flow:
```bash
./otel/check-collector-metrics.sh
```

### 6. `setup-grafana-secret.sh`
Sets up Grafana Cloud credentials for production:
```bash
./otel/setup-grafana-secret.sh
```

### 7. `test-traces.sh`
Tests trace generation by making HTTP requests:
```bash
./otel/test-traces.sh
```

## Configuration Files

### Development (`config/dev.exs`)
- Local OTLP exporter to localhost:4317
- Insecure connections for local testing
- Conditional configuration based on `OTEL_ACTIVE`

### Production (`config/prod.exs`)
- Grafana Cloud OTLP endpoint configuration
- Secure TLS connections
- Environment-based endpoint configuration

### Runtime (`config/runtime.exs`)
- Dynamic endpoint resolution
- API key management from environment variables

## Dependencies Added

### Core OpenTelemetry
- `opentelemetry`
- `opentelemetry_api`
- `opentelemetry_exporter`

### Instrumentation Libraries
- `opentelemetry_phoenix`
- `opentelemetry_bandit`
- `opentelemetry_ecto`
- `opentelemetry_cowboy`
- `opentelemetry_telemetry`

### Additional Dependencies
- `opentelemetry_process_propagator`
- `opentelemetry_semantic_conventions`

## Application Changes

### 1. `apps/privee_web/lib/privee_web/application.ex`
- Conditional OpenTelemetry setup based on `OTEL_ACTIVE`
- Phoenix and Bandit instrumentation initialization
- Graceful fallback when OTEL is disabled

### 2. `apps/privee/lib/privee/application.ex`
- Conditional Ecto instrumentation
- Database connection tracing

### 3. `apps/privee_web/lib/privee_web/telemetry.ex`
- Base metrics (always active)
- Conditional OTEL-specific metrics
- Phoenix request tracking
- Database query metrics

## Usage Examples

### Local Development (Complete Stack)
```bash
# 1. Start the complete observability stack
./otel/start-otel-stack.sh

# 2. Start Phoenix with OpenTelemetry
OTEL_ACTIVE=true mix phx.server

# 3. Generate test data
./otel/test-traces.sh

# 4. View observability data:
#    - Traces: http://localhost:16686 (Jaeger)
#    - Dashboards: http://localhost:3000 (Grafana - admin/admin)
#    - Metrics: http://localhost:9090 (Prometheus)
#    - Logs: via Grafana → Explore → Loki

# 5. Verify everything is working
./otel/verify-telemetry.sh

# 6. Stop the stack when done
./otel/stop-otel-stack.sh
```

### Quick Verification
```bash
# Check specific components
./otel/check-jaeger.sh              # Check traces
./otel/check-collector-metrics.sh   # Check OTEL Collector
```

### Production Deployment
```bash
# 1. Set up Grafana Cloud credentials
./otel/setup-grafana-secret.sh

# 2. Deploy with environment variables
export OTEL_ACTIVE=true
export GRAFANA_CLOUD_OTLP_ENDPOINT="https://otlp-gateway-prod-us-east-0.grafana.net/otlp"
export GRAFANA_CLOUD_API_KEY="your-api-key"

# 3. Start the application
mix phx.server
```

## Observability Stack

### Local Development (Complete Stack)
- **🔍 Jaeger**: Trace visualization at http://localhost:16686
- **📈 Grafana**: Unified dashboards at http://localhost:3000 (admin/admin)
- **📊 Prometheus**: Metrics storage at http://localhost:9090
- **📝 Loki**: Log aggregation at http://localhost:3100
- **⚙️ OTEL Collector**: Telemetry processing (gRPC: 4317, HTTP: 4318)
- **📈 Collector Metrics**: Internal metrics at http://localhost:8889/metrics
- **🗄️ PostgreSQL**: External database (see main README.md for setup)

### Data Flow Architecture
```
Phoenix App (OTEL_ACTIVE=true)
    ↓ (sends traces, metrics, logs)
OTEL Collector (localhost:4317)
    ↓ (routes data to)
    ├── Jaeger (traces) → Grafana
    ├── Prometheus (metrics) → Grafana
    └── Loki (logs) → Grafana
```

### Production
- **Grafana Cloud**: Complete observability platform
- **OTLP Export**: Traces, metrics, and logs
- **Dashboard Integration**: Pre-built Phoenix dashboards

## Troubleshooting

### Common Issues

1. **TLS Certificate Errors**
   - Solution: Use insecure connections for local development
   - Configuration updated in `config/dev.exs`

2. **Port Already in Use**
   - Solution: `pkill -f "mix phx.server"` to stop existing servers

3. **OTEL Not Active**
   - Check: `echo $OTEL_ACTIVE` should return "true"
   - Verify: Application logs should show OTEL initialization

### Debug Commands
```bash
# Check environment
echo $OTEL_ACTIVE

# Test configuration
./otel/test-otel-config.sh

# Verify complete stack status
docker compose -f otel/docker-compose.dev.yml ps

# Check individual services
curl -s http://localhost:16686 > /dev/null && echo "Jaeger ✅" || echo "Jaeger ❌"
curl -s http://localhost:3000 > /dev/null && echo "Grafana ✅" || echo "Grafana ❌"
curl -s http://localhost:9090 > /dev/null && echo "Prometheus ✅" || echo "Prometheus ❌"
curl -s http://localhost:3100/ready > /dev/null && echo "Loki ✅" || echo "Loki ❌"

# Comprehensive verification
./otel/verify-telemetry.sh

# Check Phoenix logs
OTEL_ACTIVE=true mix phx.server
```

## Complete Observability Endpoints

### 📊 All Available Services

| Service | URL | Purpose | Login |
|---------|-----|---------|-------|
| **🔍 Jaeger** | http://localhost:16686 | Distributed Tracing | None |
| **📈 Grafana** | http://localhost:3000 | Unified Dashboards | admin/admin |
| **📊 Prometheus** | http://localhost:9090 | Metrics Storage | None |
| **📝 Loki** | http://localhost:3100 | Log Aggregation | API only |
| **⚙️ OTEL Collector** | localhost:4317 (gRPC) | Telemetry Processing | None |
| **📈 Collector Metrics** | http://localhost:8889/metrics | Internal Metrics | None |

### 🔍 What Each Service Shows

#### Jaeger (http://localhost:16686)
- **Traces**: Individual request flows through your application
- **Services**: Your Phoenix app appears as "privee"
- **Operations**: HTTP endpoints, database queries, etc.

#### Grafana (http://localhost:3000)
- **Unified Dashboards**: Pre-built Phoenix OpenTelemetry dashboard
- **Explore**: Query traces (Jaeger), metrics (Prometheus), logs (Loki)
- **Correlation**: See traces, metrics, and logs together

#### Prometheus (http://localhost:9090)
- **Time-series Metrics**: OTEL Collector metrics, Phoenix app metrics
- **Query Interface**: PromQL queries for custom metrics analysis
- **Targets**: Shows what endpoints are being scraped

#### Loki (http://localhost:3100)
- **Centralized Logs**: All application logs in one place
- **API Access**: Query logs programmatically
- **Grafana Integration**: Best viewed through Grafana Explore

### 🎯 Verification Workflow

1. **Start Stack**: `./otel/start-otel-stack.sh`
2. **Start Phoenix**: `OTEL_ACTIVE=true mix phx.server`
3. **Generate Data**: `curl http://localhost:4000`
4. **Verify**:
   - **Traces**: Jaeger → Select "privee" service
   - **Metrics**: Grafana → Phoenix dashboard
   - **Logs**: Grafana → Explore → Loki
   - **All**: `./otel/verify-telemetry.sh`

## Metrics Collected

### Phoenix Metrics
- Request duration
- Request count by status
- Response time percentiles

### Database Metrics
- Query duration
- Connection pool usage
- Query count by operation

### System Metrics
- Memory usage
- Process counts
- Beam VM metrics

## Next Steps

1. **Custom Instrumentation**: Add business-specific traces
2. **Alerting**: Set up Grafana Cloud alerts
3. **Dashboards**: Create custom Phoenix dashboards
4. **Performance Monitoring**: Set up SLI/SLO tracking

## Files Modified/Created

### Configuration
- `config/dev.exs` - Development OTEL config
- `config/prod.exs` - Production OTEL config  
- `config/runtime.exs` - Runtime OTEL config
- `mix.exs` - Dependencies

### Application Code
- `apps/privee_web/lib/privee_web/application.ex`
- `apps/privee/lib/privee/application.ex`
- `apps/privee_web/lib/privee_web/telemetry.ex`

### Infrastructure
- `otel/docker-compose.dev.yml` - Local observability stack
- `otel/otel-collector-config.yaml` - Collector configuration
- `otel/*.sh` - Management scripts

This implementation provides a complete, production-ready OpenTelemetry solution that follows the project's conventions and can be easily enabled/disabled via environment variables.
