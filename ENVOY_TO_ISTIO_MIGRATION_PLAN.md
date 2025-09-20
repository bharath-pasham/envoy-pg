# Envoy Gateway to Istio Migration Plan

## Overview
This document outlines the comprehensive migration plan for converting the envoy-pg project from Envoy Gateway to Istio Gateway. This migration will replace problematic EnvoyPatchPolicy configurations with robust Istio EnvoyFilter implementations.

## Current Project State Analysis

### Remaining Files After Cleanup
```
├── gateway/
│   ├── 01-gateway-class.yaml              # Envoy Gateway class definition
│   ├── 02-gateway.yaml                    # Gateway instance (uses observability-gateway-class)
│   ├── 03-route-service-a.yaml            # HTTPRoute for service-a with canary routing
│   ├── 04-route-service-b.yaml            # HTTPRoute for service-b
│   ├── 07-backend-traffic-policy.yaml     # BackendTrafficPolicy for timeouts/retries/circuit breaker
│   ├── routes.yaml                        # Additional basic routes (duplicate GatewayClass/Gateway)
│   ├── filters/
│   │   └── 01-request-transform-envoygateway.yaml  # Problematic EnvoyPatchPolicy with Lua script
│   └── observability/
│       ├── envoy-observability.yaml       # EnvoyProxy config with telemetry
│       ├── observability-routes.yaml      # HTTPRoute with observability headers + BackendTrafficPolicy
│       └── observability-stack.yaml       # Prometheus/Grafana stack
└── service-a/ & service-b/                # Application deployments (no changes needed)
```

### Envoy Gateway Dependencies to Replace
1. **EnvoyPatchPolicy** - Lua script for customer tier header injection
2. **BackendTrafficPolicy** - Traffic management (timeouts, retries, circuit breaking, health checks)
3. **EnvoyProxy** - Telemetry and observability configuration
4. **GatewayClass** - Controller reference to Envoy Gateway

## Migration Strategy

### Phase 1: Infrastructure Setup
**Objective**: Install Istio and prepare the cluster

#### Prerequisites
```bash
# Install Istio CLI
curl -L https://istio.io/downloadIstio | sh -
export PATH=$PWD/istio-*/bin:$PATH

# Install Istio control plane
istioctl install --set values.pilot.enableWorkloadEntry=true --set values.telemetry.v2.enabled=true

# Enable automatic sidecar injection
kubectl label namespace default istio-injection=enabled

# Verify installation
istioctl verify-install
```

### Phase 2: Gateway Infrastructure Migration

#### 2.1 Replace GatewayClass Controller
**Files affected**: `gateway/01-gateway-class.yaml`, `gateway/routes.yaml`

**Current**:
```yaml
spec:
  controllerName: gateway.envoyproxy.io/gatewayclass-controller
```

**New Istio Configuration**:
```yaml
spec:
  controllerName: istio.io/gateway-controller
```

#### 2.2 Update Gateway Instance
**Files affected**: `gateway/02-gateway.yaml`

**Changes**:
- Change `gatewayClassName` from `observability-gateway-class` to `istio`
- Remove Envoy Gateway specific annotations
- Ensure compatibility with Istio Gateway controller

### Phase 3: Core Feature Migration

#### 3.1 Convert EnvoyPatchPolicy to EnvoyFilter
**Source**: `gateway/filters/01-request-transform-envoygateway.yaml`
**Target**: New Istio EnvoyFilter

**Current Lua Script Logic**:
- Analyzes request path to determine customer tier
- Adds `x-customer-tier` header (standard/premium/enterprise)
- Logs request information

**New Istio EnvoyFilter Configuration**:
```yaml
apiVersion: install.istio.io/v1alpha1
kind: EnvoyFilter
metadata:
  name: request-transform-filter
  namespace: istio-system
spec:
  workloadSelector:
    labels:
      istio: gateway
  configPatches:
  - applyTo: HTTP_FILTER
    match:
      context: GATEWAY
      listener:
        filterChain:
          filter:
            name: envoy.filters.network.http_connection_manager
    patch:
      operation: INSERT_BEFORE
      value:
        name: envoy.filters.http.lua
        typed_config:
          "@type": type.googleapis.com/envoy.extensions.filters.http.lua.v3.Lua
          inline_code: |
            function envoy_on_request(request_handle)
              local path = request_handle:headers():get(":path") or "/"
              local tier = "standard"
              if string.find(path, "/api/premium") then
                tier = "premium"
              elseif string.find(path, "/api/enterprise") then
                tier = "enterprise"
              end
              if not request_handle:headers():get("x-customer-tier") then
                request_handle:headers():add("x-customer-tier", tier)
              end
              request_handle:logInfo("Added customer tier: " .. tier .. " for path: " .. path)
            end
```

#### 3.2 Convert BackendTrafficPolicy to DestinationRule
**Sources**:
- `gateway/07-backend-traffic-policy.yaml`
- `gateway/observability/observability-routes.yaml` (BackendTrafficPolicy section)

**Migration Mapping**:

| Envoy Gateway Feature | Istio Equivalent | Implementation |
|----------------------|------------------|----------------|
| `timeout.tcp.connectTimeout` | `DestinationRule.trafficPolicy.connectionPool.tcp.connectTimeout` | Direct mapping |
| `timeout.http.requestTimeout` | `DestinationRule.trafficPolicy.connectionPool.http.h1MaxPendingRequests` | HTTP timeout configuration |
| `retry.*` | `VirtualService.http.retries` | Move to VirtualService |
| `circuitBreaker.*` | `DestinationRule.trafficPolicy.outlierDetection` | Circuit breaker → Outlier detection |
| `loadBalancer.type` | `DestinationRule.trafficPolicy.loadBalancer` | Load balancing configuration |
| `healthCheck.active` | `DestinationRule.trafficPolicy.healthCheck` | Health check configuration |

**New DestinationRule Configuration**:
```yaml
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: service-a-destination-rule
  namespace: default
spec:
  host: service-a.default.svc.cluster.local
  trafficPolicy:
    connectionPool:
      tcp:
        connectTimeout: 10s
      http:
        http1MaxPendingRequests: 100
        maxRequestsPerConnection: 100
    loadBalancer:
      simple: ROUND_ROBIN
    outlierDetection:
      consecutiveErrors: 5
      interval: 30s
      baseEjectionTime: 30s
      maxEjectionPercent: 50
```

### Phase 4: Observability Migration

#### 4.1 Replace EnvoyProxy Telemetry with Istio Telemetry v2
**Source**: `gateway/observability/envoy-observability.yaml`

**Istio Telemetry Configuration**:
```yaml
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
metadata:
  name: observability-config
spec:
  values:
    telemetry:
      v2:
        enabled: true
        prometheus:
          service:
          - name: envoy-stats
            port: 15090
        accessLogService:
          enabled: true
  meshConfig:
    accessLogFile: /dev/stdout
    defaultConfig:
      proxyStatsMatcher:
        inclusionRegexps:
        - ".*outlier_detection.*"
        - ".*circuit_breakers.*"
        - ".*upstream_rq_retry.*"
        - ".*_cx_.*"
        exclusionRegexps:
        - ".*osconfig.*"
```

#### 4.2 Update Prometheus Configuration
**Source**: `gateway/observability/observability-stack.yaml`

**Changes**:
- Update Prometheus scrape targets for Istio sidecar metrics (port 15090)
- Add Istio control plane metrics scraping (istiod)
- Update service discovery for Istio proxy metrics

**New Prometheus Scrape Config**:
```yaml
scrape_configs:
# Istio mesh metrics
- job_name: 'istio-mesh'
  kubernetes_sd_configs:
  - role: endpoints
    namespaces:
      names:
      - istio-system
  relabel_configs:
  - source_labels: [__meta_kubernetes_service_name, __meta_kubernetes_endpoint_port_name]
    action: keep
    regex: istio-proxy;http-monitoring

# Istio control plane
- job_name: 'istiod'
  kubernetes_sd_configs:
  - role: endpoints
    namespaces:
      names:
      - istio-system
  relabel_configs:
  - source_labels: [__meta_kubernetes_service_name, __meta_kubernetes_endpoint_port_name]
    action: keep
    regex: istiod;http-monitoring

# Application metrics through Istio sidecar
- job_name: 'istio-proxy'
  kubernetes_sd_configs:
  - role: pod
  relabel_configs:
  - source_labels: [__meta_kubernetes_pod_container_name, __meta_kubernetes_pod_container_port_name]
    action: keep
    regex: istio-proxy;http-envoy-prom
```

### Phase 5: Advanced Routing Features

#### 5.1 HTTPRoute Compatibility Validation
**Files**: `gateway/03-route-service-a.yaml`, `gateway/04-route-service-b.yaml`, `gateway/observability/observability-routes.yaml`

**Analysis**:
- Basic HTTPRoute configurations are compatible with Istio Gateway
- Header modification filters work with Istio
- Weight-based routing is supported
- Path-based routing is supported

**Required Changes**:
- Ensure `parentRefs` reference the new Istio Gateway
- Validate that complex header manipulation works with Istio's implementation
- Move retry logic from BackendTrafficPolicy to VirtualService (if needed)

#### 5.2 Advanced Header Manipulation
For complex header operations in `observability-routes.yaml`, consider converting to VirtualService for more advanced features:

```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: advanced-header-manipulation
spec:
  gateways:
  - demo-gateway
  hosts:
  - "demo.local"
  http:
  - match:
    - uri:
        prefix: /api
    headers:
      request:
        add:
          x-request-start: "%START_TIME%"
          x-trace-id: "%REQ(X-B3-TRACEID)%"
      response:
        add:
          x-response-time: "%DURATION%"
    route:
    - destination:
        host: service-a
      weight: 50
    - destination:
        host: service-b
      weight: 50
```

## Implementation Timeline

### Week 1: Infrastructure Setup
- [ ] Install Istio in the cluster
- [ ] Enable sidecar injection for default namespace
- [ ] Validate Istio installation

### Week 2: Core Migration
- [ ] Convert GatewayClass and Gateway configurations
- [ ] Migrate EnvoyPatchPolicy to EnvoyFilter
- [ ] Convert BackendTrafficPolicy to DestinationRule
- [ ] Test basic traffic flow

### Week 3: Observability Migration
- [ ] Configure Istio telemetry
- [ ] Update Prometheus scrape configurations
- [ ] Migrate access logging configuration
- [ ] Validate metrics collection

### Week 4: Testing and Validation
- [ ] Comprehensive end-to-end testing
- [ ] Performance validation
- [ ] Observability dashboard updates
- [ ] Documentation updates

## Migration Commands

### Pre-migration Cleanup
```bash
# Remove existing Envoy Gateway resources
kubectl delete -f gateway/filters/
kubectl delete -f gateway/07-backend-traffic-policy.yaml
kubectl delete -f gateway/observability/envoy-observability.yaml

# Remove BackendTrafficPolicy from observability routes
kubectl delete BackendTrafficPolicy observability-backend-policy
```

### Migration Execution
```bash
# Phase 1: Install Istio
istioctl install --set values.pilot.enableWorkloadEntry=true
kubectl label namespace default istio-injection=enabled

# Phase 2: Apply new Istio configurations
kubectl apply -f gateway/istio/01-gateway-class.yaml          # New GatewayClass
kubectl apply -f gateway/istio/02-gateway.yaml               # Updated Gateway
kubectl apply -f gateway/istio/request-transform-filter.yaml # New EnvoyFilter
kubectl apply -f gateway/istio/destination-rules.yaml       # New DestinationRules
kubectl apply -f gateway/istio/telemetry-config.yaml        # Istio telemetry

# Phase 3: Restart applications to inject sidecars
kubectl rollout restart deployment/service-a deployment/service-b

# Phase 4: Update observability stack
kubectl apply -f gateway/observability/observability-stack-istio.yaml
```

### Validation Commands
```bash
# Verify Istio installation
istioctl proxy-status

# Check gateway configuration
kubectl get gateway demo-gateway -o yaml

# Verify EnvoyFilter application
kubectl get envoyfilter -A

# Check DestinationRule configuration
kubectl get destinationrule -o wide

# Test traffic flow with customer tier headers
curl -H "Host: demo.local" http://localhost/api/premium/test

# Check Istio proxy configuration
istioctl proxy-config cluster <gateway-pod-name> -n istio-system

# Verify metrics collection
kubectl port-forward -n istio-system svc/istiod 15014:15014
curl http://localhost:15014/metrics
```

## Rollback Strategy

### Emergency Rollback
```bash
# Remove Istio configurations
kubectl delete -f gateway/istio/

# Restore Envoy Gateway configurations
kubectl apply -f gateway/01-gateway-class.yaml
kubectl apply -f gateway/02-gateway.yaml
kubectl apply -f gateway/07-backend-traffic-policy.yaml
kubectl apply -f gateway/filters/
kubectl apply -f gateway/observability/envoy-observability.yaml

# Remove sidecar injection
kubectl label namespace default istio-injection-
kubectl rollout restart deployment/service-a deployment/service-b
```

## File Change Summary

### Files to be Created (New Istio Configurations)
```
gateway/istio/
├── 01-gateway-class.yaml           # Istio GatewayClass
├── 02-gateway.yaml                 # Updated Gateway config
├── request-transform-filter.yaml   # EnvoyFilter (replaces EnvoyPatchPolicy)
├── destination-rules.yaml          # DestinationRules (replaces BackendTrafficPolicy)
├── telemetry-config.yaml          # Istio telemetry configuration
└── virtual-services.yaml          # Advanced routing (if needed)
```

### Files to be Modified
```
gateway/observability/
├── observability-stack.yaml        # Update Prometheus scrape configs for Istio
└── observability-routes.yaml       # Remove BackendTrafficPolicy section
```

### Files to be Removed/Replaced
```
gateway/
├── 01-gateway-class.yaml           # Replace with Istio version
├── 02-gateway.yaml                 # Update gatewayClassName
├── 07-backend-traffic-policy.yaml  # Convert to DestinationRule
├── routes.yaml                     # Merge/consolidate with main configs
└── filters/
    └── 01-request-transform-envoygateway.yaml  # Convert to EnvoyFilter

gateway/observability/
└── envoy-observability.yaml        # Replace with Istio telemetry config
```

## Risk Assessment

### High Risk Areas
1. **EnvoyFilter Lua Script**: Complex logic migration requires careful testing
2. **Observability Metrics**: Potential metric name changes in Istio
3. **Traffic Policies**: Circuit breaker behavior differences between Envoy Gateway and Istio
4. **Performance**: Potential latency changes with Istio sidecar architecture

### Mitigation Strategies
1. **Gradual Migration**: Migrate one service at a time
2. **Parallel Testing**: Run both configurations in parallel during transition
3. **Monitoring**: Enhanced monitoring during migration period
4. **Quick Rollback**: Maintain ability to quickly revert to Envoy Gateway

## Success Criteria

### Functional Requirements
- [ ] All HTTP routes function correctly
- [ ] Customer tier header injection works as expected
- [ ] Traffic policies (timeouts, retries, circuit breaking) behave correctly
- [ ] Canary deployment routing functions properly
- [ ] Health checks pass for all services

### Observability Requirements
- [ ] Prometheus metrics are collected correctly
- [ ] Access logs are properly formatted and accessible
- [ ] Grafana dashboards display accurate data
- [ ] Distributed tracing works end-to-end

### Performance Requirements
- [ ] Request latency remains within acceptable bounds
- [ ] Throughput does not degrade significantly
- [ ] Resource utilization is within expected limits

This migration plan provides a comprehensive roadmap for converting from Envoy Gateway to Istio Gateway while maintaining all existing functionality and improving the problematic EnvoyPatchPolicy implementation.