# Alternate Migration Plan: Envoy Gateway to Istio (Phased, Safe, Incremental)

## Objectives
- Migrate ingress & traffic policies from Envoy Gateway to Istio with zero-downtime.
- Preserve functional parity (routing, timeouts, retries, header logic).
- Introduce stronger security (mTLS) and structured observability.
- Enable progressive rollout with fast rollback.

## High-Level Strategy
1. Prepare Istio control plane & ingress gateway alongside existing Envoy Gateway (dual-run).
2. Introduce Istio traffic policy resources (DestinationRule, VirtualService) without cutting traffic.
3. Shadow / mirrored traffic validation (header based or port-based) to confirm parity.
4. Gradually shift live traffic (DNS / LB weight or explicit client header) to Istio ingress.
5. Harden (enable mTLS STRICT, apply retry/circuit breaker after baseline latency captured).
6. Decommission Envoy Gateway only after SLO stability window.

## Phases & Deliverables

### Phase 0: Repo & Manifest Preparation
Create new directory: `gateway/istio/` containing:
- `00-namespace.yaml` (if using dedicated namespace for ingress, e.g., `istio-system` already exists — skip if cluster-managed)
- `01-gateway.yaml` (Istio Kubernetes Gateway API resource referencing built-in Istio GatewayClass OR legacy Istio `Gateway` resource; choose one)
- `02-virtualservices.yaml` (Services A & B routing, weighted + canary logic)
- `03-destinationrules.yaml` (Service-level connection pools, outlier detection, health checks where possible)
- `04-envoyfilter-tier-injector.yaml` (Lua header injection for x-customer-tier)
- `05-telemetry.yaml` (Access logging + metric shaping for ingress gateway)
- `06-servicemonitor.yaml` (If Prometheus Operator present)
- `10-peer-authentication.yaml` (PERMISSIVE → STRICT progression plan)
- `11-authz-policies.yaml` (Placeholder for future RBAC/JWT if needed)
- `99-rollout-notes.md` (Operational guidance, SLOs, rollback triggers)

### Phase 1: Install / Verify Istio
(If not installed)
```
# Download + Install pinned version
ISTIO_VERSION=1.22.3
curl -L https://istio.io/downloadIstio | ISTIO_VERSION=$ISTIO_VERSION sh -
export PATH="$PWD/istio-$ISTIO_VERSION/bin:$PATH"

# Install (profile minimized + ingress)
istioctl install -y --set profile=default \
  --set values.global.proxy.logLevel=warning \
  --set meshConfig.enableTracing=false

# Label namespace for sidecar injection
kubectl label namespace default istio-injection=enabled --overwrite

# Restart workloads for sidecars
kubectl rollout restart deploy/service-a deploy/service-b
```
Validation:
```
istioctl verify-install
istioctl proxy-status
```

### Phase 2: Introduce Istio Ingress & Policies (No Traffic Yet)
1. Apply `gateway/istio/01-gateway.yaml` (bind to a distinct LoadBalancer or NodePort so you can test separately).
2. Apply VirtualServices & DestinationRules.
3. Apply EnvoyFilter (scoped to ingress only).
4. Apply Telemetry & ServiceMonitor (if required).
```
kubectl apply -f gateway/istio/01-gateway.yaml
kubectl apply -f gateway/istio/03-destinationrules.yaml
kubectl apply -f gateway/istio/02-virtualservices.yaml
kubectl apply -f gateway/istio/04-envoyfilter-tier-injector.yaml
kubectl apply -f gateway/istio/05-telemetry.yaml
kubectl apply -f gateway/istio/06-servicemonitor.yaml
```
Validation commands:
```
kubectl get gateway -A
istioctl proxy-config listeners -n istio-system $(kubectl get po -n istio-system -l istio=ingressgateway -o jsonpath='{.items[0].metadata.name}') | grep 0.0.0.0:80
istioctl proxy-config routes -n istio-system $(kubectl get po -n istio-system -l istio=ingressgateway -o jsonpath='{.items[0].metadata.name}') | grep service-a
```

### Phase 3: Shadow / Header-Based Validation
Inject a custom header (`X-Istio-Shadow: 1`) at a client or load test harness and create temporary routing rule to forward only those requests via Istio Ingress (or curl directly to Istio LB address). Compare:
```
# Envoy path
curl -H "Host: demo.local" http://<envoy-gateway-ip>/api/service-a
# Istio path
curl -H "Host: demo.local" http://<istio-gateway-ip>/api/service-a
```
Metrics parity checklist in `99-rollout-notes.md`.

### Phase 4: Gradual Traffic Shift
Options:
- DNS weight (if using external DNS/LB that supports weighting).
- Update external load balancer target group membership.
- Client header based canary (stickiness risk acknowledged).

Ramp plan (example): 5% -> 15% -> 30% -> 60% -> 100% with 30–60 min soak each. Automate checks (latency p95, error rate, retry ratio) using Prometheus queries.

### Phase 5: Harden & Optimize
1. Apply PeerAuthentication STRICT.
2. Enable retries/timeouts increments (they are present but initially commented or set conservative).
3. Tune outlier detection thresholds.
4. Add AuthorizationPolicy (allow only expected inbound host/path combos).

### Phase 6: Decommission Envoy Gateway
1. Stop new traffic (LB detach / DNS revert if rollback triggered).
2. Delete Envoy Gateway CRDs after final 24h stable metrics.
3. Remove `gateway/filters/`, `BackendTrafficPolicy` manifests.

### Rollback Strategy (Fast Path)
```
# If error spike observed during ramp
# 1. Set traffic weight back to Envoy (DNS/LB action outside manifests)
# 2. (Optional) scale Istio ingressgateway to zero to halt processing
kubectl scale deployment/istio-ingressgateway -n istio-system --replicas=0
# 3. Preserve Istio manifests for post-mortem; do NOT delete immediately.
```

## File-Level Change List
| File | Action | Notes |
|------|--------|-------|
| `gateway/filters/01-request-transform-envoygateway.yaml` | Retire | Replaced by `04-envoyfilter-tier-injector.yaml` |
| `gateway/07-backend-traffic-policy.yaml` | Retire | Logic moved to DestinationRule + VirtualService |
| `gateway/observability/envoy-observability.yaml` | Retire | Replaced with Telemetry & ServiceMonitor |
| `gateway/01-gateway-class.yaml` | Keep until cutover | Add deprecation note |
| New: `gateway/istio/01-gateway.yaml` | Add | Istio Gateway (K8s Gateway API or legacy) |
| New: `gateway/istio/02-virtualservices.yaml` | Add | Routing + canary + header rules |
| New: `gateway/istio/03-destinationrules.yaml` | Add | Connection pools, outlier detection |
| New: `gateway/istio/04-envoyfilter-tier-injector.yaml` | Add | Lua filter replacement |
| New: `gateway/istio/05-telemetry.yaml` | Add | Access log / metrics shaping |
| New: `gateway/istio/06-servicemonitor.yaml` | Add | Prometheus integration (optional) |
| New: `gateway/istio/10-peer-authentication.yaml` | Add | mTLS progression |
| New: `gateway/istio/11-authz-policies.yaml` | Add | Future RBAC/JWT examples |
| New: `gateway/istio/README.md` | Add | Apply order + explanation |
| New: `gateway/istio/99-rollout-notes.md` | Add | SLOs, smoke tests, rollback triggers |

## Command Cheat Sheet
```
# Apply all (initial non-traffic impacting resources)
kubectl apply -f gateway/istio/03-destinationrules.yaml
kubectl apply -f gateway/istio/02-virtualservices.yaml
kubectl apply -f gateway/istio/04-envoyfilter-tier-injector.yaml
kubectl apply -f gateway/istio/05-telemetry.yaml
kubectl apply -f gateway/istio/06-servicemonitor.yaml

# Enable mTLS STRICT later
kubectl apply -f gateway/istio/10-peer-authentication.yaml

# View filter injection
kubectl get envoyfilter -A

# Inspect proxy configuration
istioctl proxy-config clusters -n istio-system $(kubectl get po -n istio-system -l istio=ingressgateway -o jsonpath='{.items[0].metadata.name}') | grep service-a

# Remove legacy after cutover
kubectl delete -f gateway/filters/ --ignore-not-found
kubectl delete -f gateway/07-backend-traffic-policy.yaml --ignore-not-found
kubectl delete -f gateway/observability/envoy-observability.yaml --ignore-not-found
```

## SLO & Metrics Watch (Examples)
- Latency p95: `histogram_quantile(0.95, sum(rate(istio_request_duration_milliseconds_bucket{reporter="destination", destination_service=~"service-a.*"}[5m])) by (le))`
- Error rate: `sum(rate(istio_requests_total{response_code=~"5..", destination_service=~"service-a.*"}[5m])) / sum(rate(istio_requests_total{destination_service=~"service-a.*"}[5m]))`
- Retries: `sum(rate(istio_requests_total{response_flags=~".*URX.*"}[5m]))`

## Acceptance Criteria
- All routes reachable via Istio Gateway with parity headers.
- Canary weights honored exactly (80/20) over 5k sample requests (<3% variance).
- x-customer-tier header present and correct on 100% of eligible paths.
- No increase >15% in p95 latency during 30% traffic phase.

---
Next step: scaffold manifests under `gateway/istio/`. (Will proceed when requested.)
