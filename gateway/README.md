# Envoy Gateway Configuration

## Directory Structure

```
k8s/
├── gateway/
│   ├── 01-gateway-class.yaml         # Gateway controller definition
│   ├── 02-gateway.yaml               # Main gateway instance
│   ├── 03-route-service-a.yaml       # Service A routing rules
│   ├── 04-route-service-b.yaml       # Service B routing rules
│   ├── 05-route-load-balancing.yaml  # Load balancing examples
│   ├── 06-route-header-based.yaml    # Header-based routing
│   ├── 07-backend-traffic-policy.yaml # Timeouts, retries, circuit breakers
│   ├── 08-rate-limiting.yaml         # Rate limiting policies
│   ├── 09-security-policy.yaml       # CORS, security headers, auth
│   └── 10-observability.yaml         # Metrics and logging
```

## File Naming Convention

- **01-09**: Core configuration files (applied in order)
- **10+**: Optional/advanced features

## Configuration Components

### 1. Gateway Class (01)
Defines which controller manages the gateway (Envoy Gateway controller).

### 2. Gateway (02)
The actual gateway instance that listens for traffic on port 80/443.

### 3. Routes (03-06)
- **Service Routes (03-04)**: Direct routing to services
- **Load Balancing (05)**: Examples of weighted traffic distribution
- **Header-Based (06)**: Routing based on request headers

### 4. Traffic Policies (07-08)
- **Backend Policies (07)**: Timeouts, retries, circuit breakers
- **Rate Limiting (08)**: Request rate limits per service/path

### 5. Security (09)
- CORS configuration
- Security headers
- Basic authentication

### 6. Observability (10)
- Prometheus metrics
- Access logging
- Distributed tracing setup

## Applying Configuration

### Apply Everything
```bash
kubectl apply -f k8s/gateway/
```

### Apply in Stages

#### Stage 1: Basic Gateway Setup
```bash
kubectl apply -f k8s/gateway/01-gateway-class.yaml
kubectl apply -f k8s/gateway/02-gateway.yaml
kubectl apply -f k8s/gateway/03-route-service-a.yaml
kubectl apply -f k8s/gateway/04-route-service-b.yaml
```

#### Stage 2: Advanced Routing
```bash
kubectl apply -f k8s/gateway/05-route-load-balancing.yaml
kubectl apply -f k8s/gateway/06-route-header-based.yaml
```

#### Stage 3: Traffic Management
```bash
kubectl apply -f k8s/gateway/07-backend-traffic-policy.yaml
kubectl apply -f k8s/gateway/08-rate-limiting.yaml
```

#### Stage 4: Security & Observability
```bash
kubectl apply -f k8s/gateway/09-security-policy.yaml
kubectl apply -f k8s/gateway/