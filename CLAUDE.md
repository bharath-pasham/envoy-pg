# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an **Envoy Gateway demonstration project** showcasing a microservices architecture with two backend services (`service-a` and `service-b`) managed through Kubernetes Gateway API with Envoy Gateway controller. The project demonstrates advanced traffic management, security, and observability features.

## Architecture

### Core Components
- **Gateway Controller**: Uses Envoy Gateway controller (`gateway.envoyproxy.io/gatewayclass-controller`) to manage traffic
- **Services**: Two containerized services running on port 8080
  - `service-a`: Makes calls to `service-b` (configured via `SERVICE_B_URL` env var)
  - `service-b`: Standalone service
- **Gateway**: Single entry point (`demo-gateway`) listening on port 80 with wildcard hostname `*.demo.local`

### Configuration Structure
```
├── gateway/           # Envoy Gateway configurations (apply in numerical order)
│   ├── 01-gateway-class.yaml     # Controller definition
│   ├── 02-gateway.yaml           # Gateway instance
│   ├── 03-route-service-a.yaml   # Basic routing
│   ├── 04-route-service-b.yaml   # Basic routing
│   ├── 05-route-load-balancing.yaml  # Traffic distribution
│   ├── 06-route-header-based.yaml    # Header-based routing
│   ├── 07-backend-traffic-policy.yaml # Timeouts, retries, circuit breakers
│   ├── 08-rate-limiting.yaml     # Rate limiting policies
│   ├── 09-security-policy.yaml   # CORS, security headers, auth
│   └── 10-observability.yaml     # Metrics and logging
├── service-a/         # Service A Kubernetes manifests
└── service-b/         # Service B Kubernetes manifests
```

## Common Commands

### Kubernetes Deployment

**Deploy everything:**
```bash
kubectl apply -f gateway/
kubectl apply -f service-a/
kubectl apply -f service-b/
```

**Deploy in stages (recommended for understanding):**

Stage 1 - Basic Gateway:
```bash
kubectl apply -f gateway/01-gateway-class.yaml
kubectl apply -f gateway/02-gateway.yaml
kubectl apply -f gateway/03-route-service-a.yaml
kubectl apply -f gateway/04-route-service-b.yaml
```

Stage 2 - Advanced Routing:
```bash
kubectl apply -f gateway/05-route-load-balancing.yaml
kubectl apply -f gateway/06-route-header-based.yaml
```

Stage 3 - Traffic Management:
```bash
kubectl apply -f gateway/07-backend-traffic-policy.yaml
kubectl apply -f gateway/08-rate-limiting.yaml
```

Stage 4 - Security & Observability:
```bash
kubectl apply -f gateway/09-security-policy.yaml
kubectl apply -f gateway/10-observability.yaml
```

### Resource Management

**Check gateway status:**
```bash
kubectl get gateway demo-gateway -o yaml
kubectl get httproute -o wide
```

**View gateway controller logs:**
```bash
kubectl logs -l control-plane=envoy-gateway -n envoy-gateway-system
```

**Check service endpoints:**
```bash
kubectl get endpoints service-a service-b
kubectl get pods -l app=service-a -o wide
kubectl get pods -l app=service-b -o wide
```

## Key Configuration Details

### Service Configuration
- Both services run 2 replicas with resource limits (256Mi-512Mi memory, 100m-500m CPU)
- Services use `IfNotPresent` image pull policy (assumes local builds)
- `service-a` communicates with `service-b` via `SERVICE_B_URL=http://service-b:8080`

### Gateway Features Demonstrated
- **Load Balancing**: Weighted traffic distribution between service instances
- **Header-Based Routing**: Route requests based on HTTP headers
- **Traffic Policies**: Timeout, retry, and circuit breaker configurations
- **Rate Limiting**: Request rate limits per service/path
- **Security**: CORS, security headers, and authentication policies
- **Observability**: Prometheus metrics, access logging, distributed tracing

### Important Notes
- Gateway listens on `*.demo.local` - configure local DNS or hosts file for testing
- All configurations use `default` namespace
- Services expect to be built with tags `service-a:latest` and `service-b:latest`
- Configuration files are numbered for ordered application (01-10)