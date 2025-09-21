# Fast Migration Plan (Accepts Downtime, Minimal Security Hardening)

Goal: Replace Envoy Gateway stack with Istio ingress + traffic policy as quickly as possible. Downtime window acceptable; omit progressive rollout, mTLS, authorization, observability tuning.

## Scope Included
- Install Istio (default profile)
- Replace Envoy Gateway ingress with Istio Gateway (K8s Gateway API)
- Recreate routing (VirtualServices) and traffic policy (DestinationRules)
- Replace Lua header logic with EnvoyFilter

## Scope Excluded
- Zero-downtime / dual-run
- mTLS enablement
- Authorization / JWT
- Canary ramp strategy (weights applied immediately)
- Advanced telemetry customization beyond basic access logs

## Prerequisites
- Kubectl context points to target cluster
- Existing services: `service-a`, `service-a-canary`, `service-b` (port 8080)

## Step 1: Snapshot Current State (Optional but recommended)
```
kubectl get all -A > pre-migration-k8s-snapshot.txt
kubectl get gatewayclasses.gateway.networking.k8s.io
kubectl get gateways -A
```

## Step 2: Remove Envoy Gateway Resources (Hard Cut)
(Triggers downtime until Istio ingress is up)
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

## Step 3: Install Istio (If not already)
```
ISTIO_VERSION=1.22.3
curl -L https://istio.io/downloadIstio | ISTIO_VERSION=$ISTIO_VERSION sh -
export PATH="$PWD/istio-$ISTIO_VERSION/bin:$PATH"
istioctl install -y --set profile=default
kubectl label namespace default istio-injection=enabled --overwrite
kubectl rollout restart deploy/service-a deploy/service-b
```
Wait for pods:
```
kubectl wait --for=condition=Available deployment/service-a --timeout=120s
kubectl wait --for=condition=Available deployment/service-b --timeout=120s
```

## Step 4: Apply Istio Ingress + Policies
Use already-created manifests in `gateway/istio/` (only essentials):
```
# Order: destination rules -> virtual services -> gateway -> filter
kubectl apply -f gateway/istio/03-destinationrules.yaml
kubectl apply -f gateway/istio/02-virtualservices.yaml
kubectl apply -f gateway/istio/01-gateway.yaml
kubectl apply -f gateway/istio/04-envoyfilter-tier-injector.yaml
```

## Step 5: Basic Validation
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

## Step 6: (Optional) Simple Log Check
```
kubectl logs -n istio-system $GW_POD | grep tier-injector | tail -5
```

## Rollback (Reapply Old Envoy Stack)
If results unsatisfactory:
```
# Remove new Istio ingress config (optional)
kubectl delete -f gateway/istio/04-envoyfilter-tier-injector.yaml --ignore-not-found
kubectl delete -f gateway/istio/01-gateway.yaml --ignore-not-found
kubectl delete -f gateway/istio/02-virtualservices.yaml --ignore-not-found
kubectl delete -f gateway/istio/03-destinationrules.yaml --ignore-not-found

# Reapply previous Envoy Gateway resources
kubectl apply -f gateway/01-gateway-class.yaml
kubectl apply -f gateway/02-gateway.yaml
kubectl apply -f gateway/03-route-service-a.yaml
kubectl apply -f gateway/04-route-service-b.yaml
kubectl apply -f gateway/07-backend-traffic-policy.yaml
kubectl apply -f gateway/filters/01-request-transform-envoygateway.yaml
kubectl apply -f gateway/observability/envoy-observability.yaml
```

## Notes
- Immediate application of all policies may produce different latency/retry behavior vs previous setup; adjust DestinationRule/VirtualService if needed.
- Health checks in DestinationRules (active) are commented out; enable only if mesh config allows.
- No mTLS: traffic between sidecars is plaintext unless mesh default later changed.

## Success Criteria (Minimal)
- HTTP 200 responses from /api/service-a and /api/service-b
- Canary header route sends 100% to canary backend
- `x-customer-tier` present on tiered endpoints

End of fast migration plan.
