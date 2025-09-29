# Service Access Methods

## Current Port-Forward Setup
Your current port-forwards (recreated by `port-forwards.sh`):
- **Prometheus**: http://localhost:9090
- **Grafana**: http://localhost:3000
- **Istio Gateway**: http://localhost:8080

## Permanent Alternatives

### Option 1: NodePort Services (Recommended)
Apply the permanent services: `kubectl apply -f permanent-services.yaml`

Direct access via minikube IP (192.168.49.2):
- **Prometheus**: http://192.168.49.2:30090
- **Grafana**: http://192.168.49.2:30300
- **Istio Gateway**: http://127.0.0.1:80 (already LoadBalancer)

### Option 2: Minikube Service Command
Use minikube's built-in service exposure:
```bash
# Open services in browser
minikube service prometheus -n observability
minikube service grafana -n observability
minikube service istio-demo-gateway-istio
```

### Option 3: Minikube Tunnel (All LoadBalancers)
For a more production-like setup:
```bash
# Run in background terminal
minikube tunnel

# Access via LoadBalancer IPs shown in:
kubectl get services --all-namespaces
```

## Comparison

| Method | Pros | Cons |
|--------|------|------|
| Port-forward | Simple, localhost URLs | Temporary, dies when terminal closes |
| NodePort | Permanent, survives restarts | Different ports, need minikube IP |
| Minikube service | Auto-opens browser | Temporary URLs |
| Minikube tunnel | Production-like LB IPs | Requires sudo, runs in background |

## Recommendations

1. **For development**: Use port-forwards (`./port-forwards.sh`)
2. **For permanent access**: Apply NodePort services (`kubectl apply -f permanent-services.yaml`)
3. **For CI/automation**: Use NodePort with minikube IP
4. **For testing LoadBalancers**: Use minikube tunnel