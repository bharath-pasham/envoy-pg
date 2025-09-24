# Vector Setup for Istio Gateway Latency Metrics

This document provides step-by-step instructions to set up Vector to collect JSON logs from your `istio-demo-gateway` and generate latency metrics for Prometheus.

## Overview

**What this setup does:**
- Collects JSON logs from your `istio-demo-gateway` pods
- Parses logs to extract latency metrics (from `response_duration` field)
- Groups metrics by service (`x_service`), server name (`server_name`), and endpoint (`request_uri`)
- Exposes metrics for Prometheus to scrape
- Keeps it simple with minimal configuration

**Prerequisites:**
- Kubernetes cluster with Istio installed
- Your `istio-demo-gateway` is running and generating JSON logs
- Prometheus is already deployed (via your existing observability stack)

## Step 1: Deploy Vector

Deploy Vector as a DaemonSet to collect logs from all nodes:

```bash
# Apply the Vector DaemonSet and configuration
kubectl apply -f gateway/observability/vector/vector-daemonset.yaml
kubectl apply -f gateway/observability/vector/vector-config.yaml
```

This creates:
- `vector` namespace
- Vector DaemonSet with proper RBAC
- Vector service exposing metrics on port 9598
- ConfigMap with Vector configuration

## Step 2: Verify Vector is Running

Check that Vector pods are running:

```bash
# Check Vector pods
kubectl get pods -n vector

# Check Vector logs to ensure it's working
kubectl logs -n vector -l app=vector --tail=50
```

You should see Vector starting up and beginning to collect logs.

## Step 3: Update Prometheus Configuration

Add Vector metrics scraping to your existing Prometheus setup.

### Option A: Manual Edit (Recommended)

1. Edit your existing Prometheus configuration:
   ```bash
   kubectl edit configmap prometheus-config -n observability
   ```

2. Add this scrape job to the `scrape_configs` section:
   ```yaml
   # Vector metrics for Istio Gateway latency
   - job_name: 'vector-istio-gateway-metrics'
     kubernetes_sd_configs:
     - role: service
       namespaces:
         names:
         - vector
     relabel_configs:
     - source_labels: [__meta_kubernetes_service_label_app]
       action: keep
       regex: vector
     - source_labels: [__meta_kubernetes_service_port_name]
       action: keep
       regex: metrics
     - source_labels: [__meta_kubernetes_service_name]
       target_label: job
       replacement: vector-istio-gateway
     metrics_path: /metrics
     scrape_interval: 15s
   ```

3. Restart Prometheus to pick up the new configuration:
   ```bash
   kubectl rollout restart deployment prometheus -n observability
   ```

### Option B: Use Provided Patch

The exact configuration is also available in `gateway/observability/vector/prometheus-update-patch.yaml` for reference.

## Step 4: Generate Test Traffic

Generate some traffic to create metrics:

```bash
# Port forward to your gateway (adjust namespace if needed)
kubectl port-forward -n default svc/istio-demo-gateway 8080:80 &

# Send test requests
curl -H "Host: api.demo.local" http://localhost:8080/api/service-a/hello
curl -H "Host: api.demo.local" http://localhost:8080/api/service-b/world
curl -H "Host: api.demo.local" http://localhost:8080/api/service-a/health

# Send multiple requests for better metrics
for i in {1..10}; do
  curl -H "Host: api.demo.local" http://localhost:8080/api/service-a/hello
  sleep 1
done
```

## Step 5: Verify Metrics in Prometheus

1. Access Prometheus UI:
   ```bash
   kubectl port-forward -n observability svc/prometheus 9090:9090
   ```

2. Open http://localhost:9090 in your browser

3. Query for Vector metrics:
   ```promql
   # See all Vector metrics
   {__name__=~"vector_.*"}

   # Query latency histogram
   vector_istio_gateway_request_duration_ms

   # Query by service
   vector_istio_gateway_request_duration_ms{service="service-a"}

   # Query by endpoint
   vector_istio_gateway_request_duration_ms{request_uri="/api/service-a/hello"}

   # Calculate average latency per service
   rate(vector_istio_gateway_request_duration_ms_sum[5m]) / rate(vector_istio_gateway_request_duration_ms_count[5m])
   ```

## Step 6: Create Grafana Dashboards (Optional)

If you have Grafana in your observability stack, create dashboards using these queries:

### Latency by Service
```promql
histogram_quantile(0.95, sum(rate(vector_istio_gateway_request_duration_ms_bucket[5m])) by (service, le))
```

### Request Rate by Endpoint
```promql
sum(rate(vector_istio_gateway_request_duration_ms_count[5m])) by (request_uri)
```

### Average Response Time
```promql
sum(rate(vector_istio_gateway_request_duration_ms_sum[5m])) by (service) / sum(rate(vector_istio_gateway_request_duration_ms_count[5m])) by (service)
```

## Troubleshooting

### Vector not collecting logs
1. Check Vector pods are running:
   ```bash
   kubectl get pods -n vector
   ```

2. Check Vector logs for errors:
   ```bash
   kubectl logs -n vector -l app=vector
   ```

3. Verify gateway is generating JSON logs:
   ```bash
   kubectl logs -n default -l gateway.networking.k8s.io/gateway-name=istio-demo-gateway
   ```

### No metrics in Prometheus
1. Check Vector metrics endpoint directly:
   ```bash
   kubectl port-forward -n vector svc/vector-metrics 9598:9598
   curl http://localhost:9598/metrics | grep istio_gateway
   ```

2. Verify Prometheus is scraping Vector:
   - Go to Prometheus UI → Status → Targets
   - Look for `vector-istio-gateway-metrics` job

### Missing labels in metrics
1. Check your gateway logs include the expected fields:
   ```bash
   kubectl logs -n default -l gateway.networking.k8s.io/gateway-name=istio-demo-gateway | head -1 | jq
   ```

2. Ensure the log format includes `x_service`, `server_name`, `request_uri`, and `response_duration`

## Cleanup

To remove Vector and related resources:

```bash
kubectl delete -f gateway/observability/vector/vector-config.yaml
kubectl delete -f gateway/observability/vector/vector-daemonset.yaml
kubectl delete namespace vector
```

Don't forget to remove the Vector scrape job from your Prometheus configuration.

## Files Created

This setup created the following files in `gateway/observability/vector/`:

- `vector-daemonset.yaml` - Vector DaemonSet deployment
- `vector-config.yaml` - Vector configuration for log parsing and metrics
- `prometheus-update-patch.yaml` - Prometheus scrape configuration
- `SETUP_INSTRUCTIONS.md` - This documentation

The configuration is designed for simplicity and should work out of the box with your existing Istio and Prometheus setup.