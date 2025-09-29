# Vector Log-to-Metrics Pipeline: Complete Guide

## Overview

This document provides a comprehensive guide to the Vector-based log-to-metrics pipeline that transforms Istio Gateway access logs into Prometheus metrics. The pipeline collects structured JSON logs from Envoy proxies, processes them through Vector transforms, and exports histogram metrics for monitoring request latency and performance.

## Architecture Overview

```
┌─────────────────┐    ┌──────────────┐    ┌─────────────────┐    ┌──────────────┐
│   Envoy Proxy   │───▶│   Vector     │───▶│   Prometheus    │───▶│   Grafana    │
│  (Access Logs)  │    │ (Transform)  │    │   (Metrics)     │    │ (Dashboards) │
└─────────────────┘    └──────────────┘    └─────────────────┘    └──────────────┘
```

### Components:
1. **Envoy Proxy**: Generates structured JSON access logs
2. **Vector**: Collects, transforms, and exports metrics
3. **Prometheus**: Scrapes and stores metrics
4. **Grafana**: Visualizes metrics and creates dashboards

## Data Flow

### 1. Log Generation (Envoy/Istio)

The Istio Gateway generates structured JSON access logs through the EnvoyFilter configuration:

**Configuration**: `gateway/istio/07a-logging.yaml`

```yaml
access_log:
- name: envoy.access_loggers.file
  typed_config:
    "@type": "type.googleapis.com/envoy.extensions.access_loggers.file.v3.FileAccessLog"
    path: /dev/stdout
    log_format:
      json_format:
        "timestamp": "%START_TIME%"
        "server_name": "%REQ(:AUTHORITY)%"
        "response_duration": "%DURATION%"
        "request_command": "%REQ(:METHOD)%"
        "request_uri": "%REQ(X-ENVOY-ORIGINAL-PATH?:PATH)%"
        "request_protocol": "%PROTOCOL%"
        "status_code": "%RESPONSE_CODE%"
        "client_address": "%DOWNSTREAM_REMOTE_ADDRESS_WITHOUT_PORT%"
        "x_service": "%REQ(X-SERVICE)%"
        # ... additional fields
```

**Example Log Entry**:
```json
{
  "timestamp": "2024-01-15T10:30:45.123Z",
  "server_name": "api.example.com",
  "response_duration": "125",
  "request_command": "GET",
  "request_uri": "/api/v1/users",
  "request_protocol": "HTTP/2",
  "status_code": "200",
  "client_address": "192.168.1.100",
  "x_service": "service-a",
  "bytes_sent": "1024",
  "bytes_received": "256",
  "user_agent": "curl/7.68.0",
  "request_id": "abc123def456",
  "upstream_cluster": "outbound|8080||service-a.default.svc.cluster.local"
}
```

### 2. Log Collection (Vector Sources)

Vector collects logs from Kubernetes pods using the `kubernetes_logs` source:

```yaml
sources:
  kubernetes_logs:
    type: kubernetes_logs
    extra_namespace_label_selector: "name!=kube-system,name!=vector,name!=observability"
```

**Key Features**:
- Automatically discovers and tails logs from all pods
- Excludes system namespaces to reduce noise
- Enriches logs with Kubernetes metadata (pod labels, namespace, etc.)

### 3. Log Processing (Vector Transforms)

#### 3.1 JSON Parsing Transform

The first transform parses JSON-formatted log messages:

```yaml
parse_json:
  type: remap
  inputs: ["kubernetes_logs"]
  source: |
    # Ensure message is a string and process if it looks like JSON
    .message = to_string(.message) ?? ""
    if starts_with(.message, "{") {
      .parsed, err = parse_json(.message)
      if err == null && is_object(.parsed) {
        # Flatten the parsed JSON into the main event
        . = merge!(., .parsed)
      }
    }
```

**Processing Logic**:
1. Converts message field to string
2. Checks if message starts with `{` (JSON indicator)
3. Attempts to parse JSON content
4. Merges parsed fields into the main event object

**Before Processing**:
```json
{
  "message": "{\"timestamp\":\"2024-01-15T10:30:45.123Z\",\"response_duration\":\"125\"}",
  "kubernetes": {
    "pod_labels": {
      "gateway.networking.k8s.io/gateway-name": "istio-demo-gateway"
    }
  }
}
```

**After Processing**:
```json
{
  "message": "{\"timestamp\":\"2024-01-15T10:30:45.123Z\",\"response_duration\":\"125\"}",
  "timestamp": "2024-01-15T10:30:45.123Z",
  "response_duration": "125",
  "kubernetes": {
    "pod_labels": {
      "gateway.networking.k8s.io/gateway-name": "istio-demo-gateway"
    }
  }
}
```

#### 3.2 Gateway Filtering Transform

Filters logs to include only those from the target gateway:

```yaml
filter_gateway:
  type: filter
  inputs: ["parse_json"]
  condition: |
    exists(.kubernetes.pod_labels."gateway.networking.k8s.io/gateway-name") &&
    .kubernetes.pod_labels."gateway.networking.k8s.io/gateway-name" == "istio-demo-gateway"
```

**Filtering Logic**:
- Checks for the presence of the gateway label
- Matches only the `istio-demo-gateway`
- Reduces processing load by filtering early in the pipeline

### 4. Metrics Generation (Log-to-Metric Transform)

The core transformation converts log events to histogram metrics:

```yaml
generate_latency_metrics:
  type: log_to_metric
  inputs: ["filter_gateway"]
  metrics:
    - type: histogram
      name: istio_gateway_request_duration_ms
      field: response_duration
      tags:
        service: "{{ x_service }}"
        server_name: "{{ server_name }}"
        request_uri: "{{ request_uri }}"
        status_code: "{{ status_code }}"
        method: "{{ request_command }}"
      buckets: [1, 5, 10, 25, 50, 100, 250, 500, 1000, 2500, 5000, 10000]
```

#### Metric Configuration Breakdown:

**Metric Type**: `histogram`
- Ideal for measuring request latency distributions
- Enables percentile calculations (P50, P95, P99)
- Provides both count and sum for rate calculations

**Source Field**: `response_duration`
- Extracted from Envoy's `%DURATION%` variable
- Represents total request processing time in milliseconds

**Labels/Tags**:
- `service`: Service identifier from `x-service` header
- `server_name`: Target hostname from `:authority` header
- `request_uri`: Request path from original or rewritten path
- `status_code`: HTTP response status code
- `method`: HTTP method (GET, POST, etc.)

**Histogram Buckets**:
```
[1, 5, 10, 25, 50, 100, 250, 500, 1000, 2500, 5000, 10000] ms
```
- Covers typical web application latency ranges
- Enables accurate percentile calculations
- Balances granularity with cardinality

#### Example Metric Output:

When a log event with `response_duration: 125` is processed, Vector generates these Prometheus metrics:

```prometheus
# HELP istio_gateway_request_duration_ms Request duration histogram
# TYPE istio_gateway_request_duration_ms histogram

istio_gateway_request_duration_ms_bucket{service="service-a",server_name="api.example.com",request_uri="/api/v1/users",status_code="200",method="GET",le="1"} 0
istio_gateway_request_duration_ms_bucket{service="service-a",server_name="api.example.com",request_uri="/api/v1/users",status_code="200",method="GET",le="5"} 0
istio_gateway_request_duration_ms_bucket{service="service-a",server_name="api.example.com",request_uri="/api/v1/users",status_code="200",method="GET",le="10"} 0
istio_gateway_request_duration_ms_bucket{service="service-a",server_name="api.example.com",request_uri="/api/v1/users",status_code="200",method="GET",le="25"} 0
istio_gateway_request_duration_ms_bucket{service="service-a",server_name="api.example.com",request_uri="/api/v1/users",status_code="200",method="GET",le="50"} 0
istio_gateway_request_duration_ms_bucket{service="service-a",server_name="api.example.com",request_uri="/api/v1/users",status_code="200",method="GET",le="100"} 0
istio_gateway_request_duration_ms_bucket{service="service-a",server_name="api.example.com",request_uri="/api/v1/users",status_code="200",method="GET",le="250"} 1
istio_gateway_request_duration_ms_bucket{service="service-a",server_name="api.example.com",request_uri="/api/v1/users",status_code="200",method="GET",le="500"} 1
istio_gateway_request_duration_ms_bucket{service="service-a",server_name="api.example.com",request_uri="/api/v1/users",status_code="200",method="GET",le="1000"} 1
istio_gateway_request_duration_ms_bucket{service="service-a",server_name="api.example.com",request_uri="/api/v1/users",status_code="200",method="GET",le="2500"} 1
istio_gateway_request_duration_ms_bucket{service="service-a",server_name="api.example.com",request_uri="/api/v1/users",status_code="200",method="GET",le="5000"} 1
istio_gateway_request_duration_ms_bucket{service="service-a",server_name="api.example.com",request_uri="/api/v1/users",status_code="200",method="GET",le="10000"} 1
istio_gateway_request_duration_ms_bucket{service="service-a",server_name="api.example.com",request_uri="/api/v1/users",status_code="200",method="GET",le="+Inf"} 1
istio_gateway_request_duration_ms_count{service="service-a",server_name="api.example.com",request_uri="/api/v1/users",status_code="200",method="GET"} 1
istio_gateway_request_duration_ms_sum{service="service-a",server_name="api.example.com",request_uri="/api/v1/users",status_code="200",method="GET"} 125
```

### 5. Metrics Export (Vector Sinks)

Vector exposes metrics via Prometheus exporter:

```yaml
sinks:
  prometheus_metrics:
    type: prometheus_exporter
    inputs: ["generate_latency_metrics"]
    address: "0.0.0.0:9598"
    namespace: "vector"
```

**Configuration Details**:
- **Port**: 9598 (exposed for Prometheus scraping)
- **Namespace**: "vector" (prefixes all metric names)
- **Format**: Standard Prometheus exposition format

## Prometheus Integration

### Scrape Configuration

Prometheus scrapes Vector's metrics endpoint:

```yaml
# prometheus.yml
scrape_configs:
  - job_name: 'vector-metrics'
    static_configs:
      - targets: ['vector-service:9598']
    scrape_interval: 30s
    metrics_path: /metrics
```

### Key Prometheus Queries

#### Percentile Calculations

**P95 Latency**:
```promql
histogram_quantile(0.95,
  rate(vector_istio_gateway_request_duration_ms_bucket[5m])
)
```

**P99 by Service**:
```promql
histogram_quantile(0.99,
  rate(vector_istio_gateway_request_duration_ms_bucket{service="service-a"}[5m])
)
```

#### Request Rate Calculations

**Requests per Second**:
```promql
rate(vector_istio_gateway_request_duration_ms_count[5m])
```

**Error Rate (4xx/5xx)**:
```promql
rate(vector_istio_gateway_request_duration_ms_count{status_code=~"4..|5.."}[5m])
/
rate(vector_istio_gateway_request_duration_ms_count[5m])
```

## Extending the Pipeline

### Adding New Metrics

To add a request count metric:

```yaml
generate_request_count:
  type: log_to_metric
  inputs: ["filter_gateway"]
  metrics:
    - type: counter
      name: istio_gateway_requests_total
      tags:
        service: "{{ x_service }}"
        status_code: "{{ status_code }}"
        method: "{{ request_command }}"
```

### Service-Specific Processing

Create separate transforms for different services:

```yaml
filter_service_a:
  type: filter
  inputs: ["parse_json"]
  condition: '.x_service == "service-a"'

filter_service_b:
  type: filter
  inputs: ["parse_json"]
  condition: '.x_service == "service-b"'
```

### Error Handling

Add error metrics for failed parsing:

```yaml
track_parse_errors:
  type: log_to_metric
  inputs: ["kubernetes_logs"]
  metrics:
    - type: counter
      name: vector_log_parse_errors_total
      tags:
        source: "{{ kubernetes.pod_name }}"
      increment_by_value: |
        if starts_with(.message, "{") {
          .parsed, err = parse_json(.message)
          if err != null { 1 } else { 0 }
        } else { 0 }
```

## Performance Considerations

### Resource Requirements

**CPU Usage**:
- JSON parsing: ~0.1 CPU cores per 1000 logs/sec
- Metric generation: ~0.05 CPU cores per 1000 logs/sec
- Overall: Plan for 0.2-0.3 CPU cores per 1000 logs/sec

**Memory Usage**:
- Base Vector process: ~50MB
- Buffer memory: ~10MB per 10,000 buffered events
- Metric storage: ~1KB per unique label combination

### Optimization Strategies

1. **Early Filtering**: Filter logs as early as possible in the pipeline
2. **Selective Labels**: Use only necessary labels to control cardinality
3. **Buffer Tuning**: Adjust buffer sizes based on log volume
4. **Batch Processing**: Enable batching for high-throughput scenarios

### Monitoring the Pipeline

Key metrics to monitor:

```promql
# Vector processing rate
rate(vector_component_received_events_total[5m])

# Vector errors
rate(vector_component_errors_total[5m])

# Buffer utilization
vector_buffer_events / vector_buffer_max_events
```

## Troubleshooting

### Common Issues

**1. Missing Metrics**
- Check Vector logs for parsing errors
- Verify log format matches expected JSON structure
- Confirm filter conditions are not too restrictive

**2. High Cardinality**
- Review label combinations
- Consider aggregating or sampling high-cardinality labels
- Monitor Prometheus memory usage

**3. Performance Issues**
- Enable Vector's internal metrics
- Monitor buffer sizes and processing rates
- Consider increasing Vector resources

### Debugging Commands

**View Vector Logs**:
```bash
kubectl logs -n vector deployment/vector -f
```

**Test JSON Parsing**:
```bash
echo '{"response_duration": "125"}' | vector --config vector-test.yaml
```

**Check Prometheus Targets**:
```bash
curl http://prometheus:9090/api/v1/targets
```

## Best Practices

1. **Label Design**: Keep labels meaningful but limited in cardinality
2. **Bucket Selection**: Choose histogram buckets based on actual latency patterns
3. **Monitoring**: Monitor the pipeline itself with metrics and alerts
4. **Testing**: Test transforms with sample data before production deployment
5. **Documentation**: Document any custom transforms or label meanings

## Security Considerations

1. **Sensitive Data**: Ensure logs don't contain sensitive information
2. **Access Control**: Restrict access to Vector configuration and metrics endpoints
3. **Network Security**: Use TLS for metrics scraping in production
4. **Log Retention**: Configure appropriate log retention policies

---

This pipeline provides a robust foundation for converting Istio Gateway access logs into actionable Prometheus metrics, enabling comprehensive monitoring and alerting for your service mesh traffic.