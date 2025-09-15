# Service Access Strategy for Kubernetes Environment

## Overview

Your Kubernetes environment has multiple ways to access services. This document outlines all available methods and their best use cases.

## Current Architecture

### Services Deployed
- **Service A**: ClusterIP service on port 8080
- **Service B**: ClusterIP service on port 8080
- **Gateway**: Demo Gateway with HTTP routing

### Gateway Configuration
- **Gateway Name**: demo-gateway
- **Hostnames**: 
  - `demo.local`
  - `service-a.demo.local`
  - `service-b.demo.local`
  - `api.demo.local`
- **Routes**: Configured for path-based routing

## Access Methods

### 1. Port-Forward (Development/Testing)

#### Direct Service Access
```bash
# Service A
kubectl port-forward svc/service-a 9999:8080
curl http://localhost:9999/api/service-a/hello

# Service B
kubectl port-forward svc/service-b 9998:8080
curl http://localhost:9998/api/service-b/hello
```

#### Pod-Level Access
```bash
# Get pod names
SERVICE_A_POD=$(kubectl get pods -l app=service-a -o jsonpath='{.items[0].metadata.name}')
SERVICE_B_POD=$(kubectl get pods -l app=service-b -o jsonpath='{.items[0].metadata.name}')

# Port-forward to specific pods
kubectl port-forward pod/$SERVICE_A_POD 9999:8080
kubectl port-forward pod/$SERVICE_B_POD 9998:8080
```

### 2. Gateway API Access (Production/Integration)

#### Through Gateway IP
```bash
# Get gateway IP
GATEWAY_IP=$(kubectl get gateway demo-gateway -o jsonpath='{.status.addresses[0].value}')

# Access services via gateway
curl -H "Host: service-a.demo.local" http://$GATEWAY_IP/api/service-a/hello
curl -H "Host: service-b.demo.local" http://$GATEWAY_IP/api/service-b/hello
curl -H "Host: api.demo.local" http://$GATEWAY_IP/api/service-a/hello
```

#### Local DNS Setup
Add to `/etc/hosts`:
```
127.0.0.1 demo.local service-a.demo.local service-b.demo.local api.demo.local
```

Then access via port-forward to gateway:
```bash
kubectl port-forward svc/demo-gateway 8080:80
curl -H "Host: service-a.demo.local" http://localhost:8080/api/service-a/hello
```

### 3. In-Cluster Access

#### Service-to-Service Communication
```bash
# Test from within cluster
kubectl run test-pod --image=curlimages/curl --rm -it -- \
  curl http://service-a:8080/api/service-a/hello

kubectl run test-pod --image=curlimages/curl --rm -it -- \
  curl http://service-b:8080/api/service-b/hello
```

### 4. LoadBalancer Access (If Supported)

If your cluster supports LoadBalancer services:
```bash
# Check if external IP is assigned
kubectl get svc demo-gateway

# Access directly
curl http://<external-ip>/api/service-a/hello
```

## Service Endpoints

### Service A Endpoints
- **Direct**: `http://service-a:8080`
- **Health Check**: `http://service-a:8080/health`
- **API**: `http://service-a:8080/api/service-a/hello`
- **Gateway Path**: `/api/service-a/*`
- **Gateway Health**: `/health/service-a`

### Service B Endpoints
- **Direct**: `http://service-b:8080`
- **Health Check**: `http://service-b:8080/health`
- **API**: `http://service-b:8080/api/service-b/hello`
- **Gateway Path**: `/api/service-b/*`
- **Gateway Health**: `/health/service-b`

## Recommended Access Patterns

### Development Workflow
1. **Quick Testing**: Use port-forward to specific services
2. **Integration Testing**: Use gateway with proper host headers
3. **Debugging**: Use pod-level port-forward for logs and debugging

### Production Workflow
1. **External Access**: Through gateway with LoadBalancer or Ingress
2. **Service Mesh**: Use service discovery and mesh routing
3. **Monitoring**: Access via gateway with observability policies

## Security Considerations

### Port-Forward Security
- Only use for development/testing
- Avoid exposing sensitive services
- Use RBAC to control port-forward permissions

### Gateway Security
- Implement authentication policies
- Use TLS termination
- Apply rate limiting and security policies

## Troubleshooting Commands

### Service Health
```bash
# Check service status
kubectl get svc service-a service-b

# Check endpoints
kubectl get endpoints service-a service-b

# Check gateway status
kubectl get gateway demo-gateway
kubectl describe gateway demo-gateway

# Check HTTPRoutes
kubectl get httproute
```

### Connectivity Testing
```bash
# Test service connectivity
kubectl run test-pod --image=curlimages/curl --rm -it -- \
  curl -v http://service-a:8080/health

# Test gateway routing
kubectl run test-pod --image=curlimages/curl --rm -it -- \
  curl -v -H "Host: service-a.demo.local" http://demo-gateway/api/service-a/hello
```

## Quick Reference

### Service A Access
```bash
# Port-forward
kubectl port-forward svc/service-a 9999:8080
curl http://localhost:9999/api/service-a/hello

# Gateway
curl -H "Host: service-a.demo.local" http://<gateway-ip>/api/service-a/hello
```

### Service B Access
```bash
# Port-forward
kubectl port-forward svc/service-b 9998:8080
curl http://localhost:9998/api/service-b/hello

# Gateway
curl -H "Host: service-b.demo.local" http://<gateway-ip>/api/service-b/hello
```

## Next Steps

1. **Choose Access Method**: Select based on your use case (dev/prod)
2. **Set Up Monitoring**: Use the observability policies for metrics
3. **Implement Security**: Apply security policies for production
4. **Scale Appropriately**: Use load balancing and rate limiting as needed