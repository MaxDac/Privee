# OpenTelemetry Integration with Grafana Cloud

This document describes how to set up OpenTelemetry in the Privee application to send telemetry data to Grafana Cloud's free tier.

## File Organization

All OpenTelemetry-related files are organized in the `otel/` folder for logical grouping:
- **Configuration files**: Docker Compose, OTEL Collector config, shell scripts
- **Documentation**: Setup guides and README
- **Shell scripts**: Executable scripts for development workflow (no Makefiles used)

This separation keeps OTEL concerns isolated while maintaining project conventions.

## Environment Variable Control

OpenTelemetry activation is controlled by the `OTEL_ACTIVE` environment variable:

- **`OTEL_ACTIVE=true`**: Enables full OpenTelemetry instrumentation and export
- **`OTEL_ACTIVE=false`** or **unset**: Disables OpenTelemetry completely (default)

This approach allows developers to:
- Run without observability overhead for normal development
- Enable detailed telemetry only when debugging or profiling
- Use the same codebase for both scenarios

## Overview

The application has been instrumented with OpenTelemetry to collect:
- **Traces**: Request/response flows through Phoenix and Ecto
- **Metrics**: HTTP server metrics, database query metrics, and VM metrics
- **Logs**: Application logs with trace correlation

## Architecture

```
Privee App → OpenTelemetry Exporter → Grafana Cloud OTLP Gateway → Grafana Observability Stack
```

## Dependencies Added

The following OpenTelemetry packages were added to both `apps/privee/mix.exs` and `apps/privee_web/mix.exs`:

```elixir
{:opentelemetry, "~> 1.5"},
{:opentelemetry_api, "~> 1.4"},
{:opentelemetry_exporter, "~> 1.8"},
{:opentelemetry_ecto, "~> 1.2"},
{:opentelemetry_phoenix, "~> 1.2"},
{:opentelemetry_cowboy, "~> 0.2"},
{:opentelemetry_bandit, "~> 0.1"}  # Only in privee_web
```

## Configuration

### Configuration Hierarchy

OpenTelemetry configuration follows this hierarchy (later configs override earlier ones):

1. **config/config.exs**: Base OpenTelemetry setup
2. **config/{env}.exs**: Environment-specific defaults (dev/test/prod)
3. **config/runtime.exs**: Runtime overrides based on environment variables (production only)

### Environment Variables

The following environment variables are used for **runtime configuration in production**:

- `OTEL_SERVICE_NAME`: Service name for OpenTelemetry (overrides default "privee")
- `OTEL_SERVICE_VERSION`: Service version (overrides default "0.1.0")
- `OTEL_EXPORTER_OTLP_ENDPOINT`: Grafana Cloud OTLP endpoint (overrides default)
- `GRAFANA_OTEL_TOKEN`: Base64 encoded authentication token for Grafana Cloud
- `OTEL_RESOURCE_ATTRIBUTES`: Additional resource attributes (format: key1=value1,key2=value2)

**Important**: Runtime configuration in `config/runtime.exs` only applies when:
- Running in **production** environment (`config_env() == :prod`)
- Environment variables are **explicitly set**

This ensures that:
- **Development** uses local OTEL collector (Jaeger)
- **Test** disables OpenTelemetry completely
- **Production** can be configured via environment variables without breaking other environments

### Grafana Cloud Setup

1. **Sign up for Grafana Cloud**: Go to [grafana.com](https://grafana.com) and create a free account
2. **Get OTLP credentials**: In your Grafana Cloud stack, go to "Connections" → "Add new connection" → "OpenTelemetry"
3. **Copy the endpoint**: Usually in the format `https://otlp-gateway-prod-<region>.grafana.net:443`
4. **Generate a token**: Create an API token with the appropriate permissions
5. **Encode the token**: The token should be base64 encoded in the format `instanceId:token`

### Local Development

For local development, you can use the provided Docker Compose setup:

```bash
# Start local observability stack
docker compose -f docker-compose.dev.yml up -d

# Access Jaeger UI
open http://localhost:16686
```

This sets up:
- **Jaeger**: For trace visualization at http://localhost:16686
- **OpenTelemetry Collector**: For receiving and processing telemetry
- **PostgreSQL**: For local database development

## Kubernetes Deployment

### Required Secrets

Create the Grafana token secret:

```bash
# Replace YOUR_GRAFANA_TOKEN with your actual token
echo -n "YOUR_GRAFANA_TOKEN" | base64
kubectl create secret generic grafana-otel-secret \
  --from-literal=GRAFANA_OTEL_TOKEN="<base64-encoded-token>"

# Or use the interactive setup script
./.azure/k8s/setup-grafana-secret.sh
```

### Network Policies

The deployment includes network policies to allow:
- DNS resolution
- HTTPS traffic to Grafana Cloud endpoints
- Communication within the cluster
- OTLP protocol traffic (ports 4317/4318)

### Firewall Requirements

Ensure your AKS cluster can reach:
- `otlp-gateway-prod-eu-west-2.grafana.net:443` (or your region's endpoint)
- DNS resolution for `*.grafana.net`

## Instrumentation Details

### Phoenix Instrumentation

- **HTTP requests**: Automatic tracing of all HTTP requests
- **Route information**: Traces include route patterns and HTTP methods
- **Response times**: Duration metrics for all endpoints
- **Error tracking**: Automatic error span recording

### Ecto Instrumentation

- **Database queries**: All SQL queries are traced
- **Query performance**: Duration, queue time, and decode time metrics
- **Connection pooling**: Pool usage and connection metrics

### Custom Metrics

Additional metrics are collected:
- VM memory usage
- Process queue lengths
- Custom business metrics (can be added as needed)

## Monitoring Dashboards

In Grafana Cloud, you can create dashboards to monitor:

1. **Application Performance Monitoring (APM)**:
   - Request rate, latency, and error rate
   - Service dependencies and call paths
   - Database query performance

2. **Infrastructure Monitoring**:
   - Pod resource usage
   - Node health and capacity
   - Network traffic patterns

3. **Business Metrics**:
   - User sessions and chat activity
   - Feature usage patterns
   - Application-specific KPIs

## Alerting

Set up alerts for:
- High error rates (>1% 4xx/5xx responses)
- Slow response times (>2s P95)
- Database connectivity issues
- High memory usage (>80% of limits)
- Pod restart loops

## Troubleshooting

### Common Issues

1. **No data in Grafana**: Check token configuration and network connectivity
2. **High memory usage**: Adjust batch processor settings in configuration
3. **Missing traces**: Verify instrumentation setup in application code

### Debug Commands

```bash
# Check OpenTelemetry configuration
kubectl logs -l app=privee | grep -i otel

# Verify network connectivity
kubectl exec -it deployment/privee -- nslookup otlp-gateway-prod-eu-west-2.grafana.net

# Check secret configuration
kubectl get secret grafana-otel-secret -o yaml

# Test configuration in different environments
MIX_ENV=dev mix run -e "IO.inspect(Application.get_env(:opentelemetry, :processors))"
MIX_ENV=test mix run -e "IO.inspect(Application.get_env(:opentelemetry, :traces_exporter))"
MIX_ENV=prod mix run -e "IO.inspect(Application.get_env(:opentelemetry, :processors))"
```

### Configuration Verification

To verify your OpenTelemetry configuration is working correctly:

```elixir
# In IEx or your application
:opentelemetry.get_tracer(:privee)
|> :otel_tracer.start_span("test_span", %{})
|> :otel_span.end_span()
```

## Security Considerations

- Store Grafana tokens in Kubernetes secrets
- Use network policies to restrict egress traffic
- Regularly rotate authentication tokens
- Monitor for unusual telemetry volume spikes

## Cost Management

Grafana Cloud free tier includes:
- 50GB logs per month
- 10,000 series for metrics
- 50GB traces per month

Monitor your usage in the Grafana Cloud dashboard to avoid overages.
