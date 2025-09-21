# Fast Istio Migration Plan (Downtime Accepted, Harden Later)

Goal: Replace Envoy Gateway stack with Istio ingress + traffic policy as quickly as possible while correcting critical gaps noted in the critique (GatewayClass, gateway reference formatting, validation & rollback safety). Downtime is acceptable; security hardening and advanced tuning deferred.

## Scope Included
- Install / verify Istio (default profile)
- Create/verify `GatewayClass` = `istio`
- Replace Envoy Gateway ingress with Istio Gateway (K8s Gateway API)
- Recreate routing (VirtualServices) & traffic policy (DestinationRules)
- Replace Lua tier header logic with EnvoyFilter (logging consistency improved)
- Basic observability (builtin metrics / access logs)

## Added Improvements vs Original Fast Plan
- GatewayClass verification & manifest (`gateway/istio/00-gatewayclass.yaml`)
- Correct VirtualService `gateways` references (`istio-demo-gateway`)
- Pre-migration checklist for services, endpoints, and current gateway reachability
- Expanded validation: routing matrix, header injection, sidecar presence
- Clear enable path for (optional) active health checks
- Safer rollback: remove namespace label + restart to evict sidecars
- Risk matrix & success criteria clarified
- Placeholders for future rate limiting & security enhancements

## Scope Excluded (Explicitly Deferred)
- Zero-downtime / dual-run (cut-over causes a short outage)
- mTLS enablement
- Authorization / JWT / RBAC
- Progressive canary weight shifting (weights applied immediately)
- Custom rate limiting implementation (placeholder only)
- Advanced telemetry customization (WASM / custom filters)
- WAF, bot detection, exhaustive security headers

## Prerequisites
- Kubectl context points to target cluster
- Existing services: `service-a`, `service-a-canary`, `service-b` (port 8080)
- Cluster supports Kubernetes Gateway API CRDs (install if missing)
- Sufficient downtime window approved

## Step 0: Pre-Migration Checklist (Run & Record)
```
kubectl get svc service-a service-a-canary service-b
kubectl get endpoints service-a service-a-canary service-b
kubectl get pods -l app=service-a -o wide
kubectl get gatewayclasses.gateway.networking.k8s.io || true
kubectl get gateways -A || true
# (Current ingress reachability, adjust IP / Host)
curl -H "Host: demo.local" http://$CURRENT_INGRESS_IP/api/service-a || true
```
Record outputs (audit + rollback reference).

## Step 1: Snapshot Current State (Optional but Recommended)
```
kubectl get all -A > pre-migration-k8s-snapshot.txt
kubectl get gatewayclasses.gateway.networking.k8s.io
kubectl get gateways -A
```

## Step 2: Remove Envoy Gateway Resources (Hard Cut)
Traffic will be down until new Istio ingress becomes active.
```
# Remove filter & traffic policies
kubectl delete -f gateway/filters/ --ignore-not-found
kubectl delete -f gateway/07-backend-traffic-policy.yaml --ignore-not-found
kubectl delete -f gateway/observability/envoy-observability.yaml --ignore-not-found || true

# Remove Gateway & related routes (HTTPRoute)
kubectl delete -f gateway/03-route-service-a.yaml --ignore-not-found
kubectl delete -f gateway/04-route-service-b.yaml --ignore-not-found
kubectl delete -f gateway/routes.yaml --ignore-not-found
kubectl delete -f gateway/02-gateway.yaml --ignore-not-found
kubectl delete -f gateway/01-gateway-class.yaml --ignore-not-found
```

## Step 3: Install / Verify Istio
```
ISTIO_VERSION=1.22.3
curl -L https://istio.io/downloadIstio | ISTIO_VERSION=$ISTIO_VERSION sh -
export PATH="$PWD/istio-$ISTIO_VERSION/bin:$PATH"
istioctl install -y --set profile=default
kubectl wait --for=condition=Available deployment/istiod -n istio-system --timeout=300s
istioctl verify-install
kubectl label namespace default istio-injection=enabled --overwrite
kubectl rollout restart deploy/service-a deploy/service-b  # ensure sidecar injection
```
Wait for pods:
```
kubectl wait --for=condition=Available deployment/service-a --timeout=120s
kubectl wait --for=condition=Available deployment/service-b --timeout=120s
```

## Step 4: Create / Verify GatewayClass & Apply Ingress Policies
Apply manifests in dependency-safe order (class -> dest rules -> virtual services -> gateway -> filters):
```
kubectl get gatewayclass istio || kubectl apply -f gateway/istio/00-gatewayclass.yaml
kubectl apply -f gateway/istio/03-destinationrules.yaml
kubectl apply -f gateway/istio/02-virtualservices.yaml
kubectl apply -f gateway/istio/01-gateway.yaml
kubectl apply -f gateway/istio/04-envoyfilter-tier-injector.yaml
```
Confirm gateway programmed:
```
kubectl get gateway istio-demo-gateway -o yaml | grep -i programmed || true
```

## Step 5: Validation Matrix
### 5.1 Gateway & Listener
```
GW_POD=$(kubectl get pod -n istio-system -l istio=ingressgateway -o jsonpath='{.items[0].metadata.name}')
istioctl proxy-status | grep ingressgateway
istioctl proxy-config listeners -n istio-system $GW_POD | grep 0.0.0.0:80
```
### 5.2 External IP / Port
```
kubectl get svc -n istio-system istio-ingressgateway
export INGRESS_IP=$(kubectl get svc -n istio-system istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
```
### 5.3 Routing (Normal, Weighted, Canary, Health, Tier)
```
curl -H "Host: demo.local" http://$INGRESS_IP/api/service-a | head -5
curl -H "Host: demo.local" http://$INGRESS_IP/api/service-b | head -5
curl -H "Host: demo.local" -H "X-Canary: true" http://$INGRESS_IP/api/service-a -v 2>&1 | grep -i x-version
curl -H "Host: demo.local" http://$INGRESS_IP/health/service-a -v | grep HTTP/
curl -H "Host: demo.local" http://$INGRESS_IP/api/premium/test -v 2>&1 | grep -i x-customer-tier
```
### 5.4 Sidecar Injection Verification
```
kubectl get pods -o jsonpath='{range .items[*]}{.metadata.name}: {.spec.containers[*].name}{"\n"}{end}' | grep istio-proxy
```
### 5.5 Weighted Split Quick Sample (best-effort)
```
for i in {1..20}; do curl -s -H "Host: demo.local" http://$INGRESS_IP/api/service-a | grep -i x-version >> /tmp/a_versions.txt; done
grep -c weighted /tmp/a_versions.txt; grep -c canary /tmp/a_versions.txt
```
```
GW_POD=$(kubectl get pod -n istio-system -l istio=ingressgateway -o jsonpath='{.items[0].metadata.name}')
# Check listener present
istioctl proxy-config listeners -n istio-system $GW_POD | grep 0.0.0.0:80
# Send test requests (replace <LB_IP> with external address or use port-forward)
# If using NodePort/LoadBalancer, get service:
kubectl get svc -n istio-system istio-ingressgateway

curl -H "Host: demo.local" http://<INGRESS_IP>/api/service-a | sed -n '1,5p'
curl -H "Host: demo.local" http://<INGRESS_IP>/api/service-b | sed -n '1,5p'
# Canary header path
curl -H "Host: demo.local" -H "X-Canary: true" http://<INGRESS_IP>/api/service-a
# Tier header check (premium path assumed)
curl -v -H "Host: demo.local" http://<INGRESS_IP>/api/premium/test 2>&1 | grep -i x-customer-tier
```

## Step 6: (Optional) Log & Config Inspection
```
kubectl logs -n istio-system $GW_POD | grep tier-injector | tail -5
istioctl proxy-config routes -n istio-system $GW_POD | head -40
```

## (Optional) Enabling Active HTTP Health Checks
Uncomment `healthCheck` block in `gateway/istio/03-destinationrules.yaml` for `service-b` (and add to others if desired) then:
```
kubectl apply -f gateway/istio/03-destinationrules.yaml
```
Monitor outlier info via metrics / logs. Note: Active health checks require mesh support; verify your Istio version/meshConfig.

## (Deferred) Rate Limiting Placeholder
Not migrated from Envoy for speed. Options later:
1. Local rate limit EnvoyFilter at ingress
2. Istio extension provider (e.g., Envoy external rate limit service)
3. WASM plugin

Track as a post-migration hardening task.

## Rollback (Reapply Envoy Stack)
If results are unsatisfactory and you need to revert quickly:
```
# Remove new Istio ingress config (optional)
kubectl delete -f gateway/istio/04-envoyfilter-tier-injector.yaml --ignore-not-found
kubectl delete -f gateway/istio/01-gateway.yaml --ignore-not-found
kubectl delete -f gateway/istio/02-virtualservices.yaml --ignore-not-found
kubectl delete -f gateway/istio/03-destinationrules.yaml --ignore-not-found

# Remove gatewayclass only if it was cluster‑local and unused elsewhere
# kubectl delete -f gateway/istio/00-gatewayclass.yaml --ignore-not-found

# Reapply previous Envoy Gateway resources
kubectl apply -f gateway/01-gateway-class.yaml
kubectl apply -f gateway/02-gateway.yaml
kubectl apply -f gateway/03-route-service-a.yaml
kubectl apply -f gateway/04-route-service-b.yaml
kubectl apply -f gateway/07-backend-traffic-policy.yaml
kubectl apply -f gateway/filters/01-request-transform-envoygateway.yaml
kubectl apply -f gateway/observability/envoy-observability.yaml

# Remove sidecars (so old Envoy path fully authoritative)
kubectl label namespace default istio-injection- || true
kubectl rollout restart deploy/service-a deploy/service-b
```

## Notes & Operational Considerations
- Retry / timeout semantics may differ; tune in DestinationRules & VirtualServices post-cutover.
- Active health checks disabled initially to reduce config risk.
- No mTLS: plaintext inside cluster until security phase.
- Logging: Lua filter now logs consistent `[tier-injector] tier=<tier> path=<path>` lines.
- Future Hardening Backlog: mTLS, AuthZ, Rate Limiting, Security Headers, Enhanced Observability, DDoS protections.

## Risk Matrix (Condensed)
| Risk | Impact | Mitigation |
|------|--------|------------|
| Missing GatewayClass | Ingress fails | Add/apply 00-gatewayclass prior to gateway |
| Wrong gateway ref in VirtualService | Traffic drop | Corrected to `istio-demo-gateway` |
| Sidecar injection failure | Policy bypass | Validate with sidecar listing step |
| Disabled active health checks | Slower failure detection | Optional enable section |
| Lack of rate limiting | Abuse risk | Post-migration task |

## Success Criteria (Minimal + Enhanced)
Minimal:
- 200 responses from /api/service-a and /api/service-b
- Canary header yields canary response (100% when header present)
- `x-customer-tier` injected on premium path

Enhanced (Recommended to capture):
- Weighted distribution approximates 80/20 across sample set
- No 5xx spikes in gateway / backend pods during first 10 minutes
- All product pods have `istio-proxy` container present
- `istioctl proxy-status` shows healthy ingress

End of improved fast migration plan.
