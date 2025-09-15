# Kubernetes Port-Forward Troubleshooting Guide

## Problem Analysis

Based on your kubectl port-forward session, you encountered two common issues:

### Issue 1: Connection Refused
```bash
kubectl port-forward svc/service-a 9999:8080 &
curl http://localhost:9999/api/service-a/hello
# Result: curl: (7) Failed to connect to localhost port 9999
```

**Root Cause**: The curl command executed immediately before the port-forward was fully established.

### Issue 2: Port Already in Use
```bash
kubectl port-forward svc/service-a 9999:8080 &
# Result: Unable to listen on port 9999: bind: address already in use
```

**Root Cause**: The previous port-forward process was still running in the background.

## Solutions

### 1. Proper Port-Forward Management

#### Method A: Foreground Port-Forward (Recommended for Testing)
```bash
# Kill any existing port-forwards
pkill -f "port-forward.*9999" || true

# Start in foreground
kubectl port-forward svc/service-a 9999:8080

# In another terminal, test the connection
curl http://localhost:9999/api/service-a/hello
```

#### Method B: Background with Delay
```bash
# Kill existing processes
pkill -f "port-forward.*9999" || true

# Start background with proper timing
kubectl port-forward svc/service-a 9999:8080 &
sleep 3  # Wait for establishment
curl http://localhost:9999/api/service-a/hello

# Clean up when done
kill %1  # Kill the background job
```

### 2. Service Verification

Before port-forwarding, verify your service is running:

```bash
# Check service exists
kubectl get svc service-a

# Check endpoints are available
kubectl get endpoints service-a

# Verify pods are running
kubectl get pods -l app=service-a

# Check service logs
kubectl logs -l app=service-a --tail=10
```

### 3. Alternative Access Methods

Since you have Gateway API configured, consider these alternatives:

#### Access via Gateway
```bash
# Get gateway IP (if LoadBalancer)
kubectl get gateway demo-gateway

# Access through gateway
curl -H "Host: service-a.demo.local" http://<gateway-ip>/api/service-a/hello
curl -H "Host: api.demo.local" http://<gateway-ip>/api/service-a/hello
```

#### Port-Forward to Pod Directly
```bash
# Get pod name
POD_NAME=$(kubectl get pods -l app=service-a -o jsonpath='{.items[0].metadata.name}')

# Port-forward to specific pod
kubectl port-forward pod/$POD_NAME 9999:8080
```

### 4. Port-Forward Helper Script

Create this script for reliable port-forward management:

```bash
#!/bin/bash
# save as: port-forward-service-a.sh

SERVICE="service-a"
LOCAL_PORT="9999"
REMOTE_PORT="8080"

# Kill existing port-forwards
echo "Cleaning up existing port-forwards..."
pkill -f "port-forward.*$LOCAL_PORT" || true
sleep 1

# Start port-forward
echo "Starting port-forward for $SERVICE..."
kubectl port-forward svc/$SERVICE $LOCAL_PORT:$REMOTE_PORT &
PID=$!

# Wait for establishment
echo "Waiting for port-forward to establish..."
for i in {1..10}; do
    if curl -s http://localhost:$LOCAL_PORT/health > /dev/null 2>&1; then
        echo "Port-forward established successfully!"
        break
    fi
    sleep 1
done

echo "Service available at: http://localhost:$LOCAL_PORT/api/service-a/hello"
echo "Press Ctrl+C to stop port-forward"

# Keep script running
wait $PID
```

### 5. Common Troubleshooting Commands

```bash
# Check what's using port 9999
lsof -i :9999
netstat -an | grep 9999

# Check port-forward processes
ps aux | grep port-forward

# Kill all kubectl port-forwards
pkill kubectl

# Test service connectivity from within cluster
kubectl run test-pod --image=curlimages/curl --rm -it -- curl http://service-a:8080/api/service-a/hello

# Check service details
kubectl describe svc service-a
kubectl describe endpoints service-a
```

## Your Service Configuration

Based on your setup:
- **Service Name**: service-a
- **Service Port**: 8080
- **Target Port**: 8080
- **Service Type**: ClusterIP
- **Available Paths**: 
  - `/api/service-a/hello`
  - `/service-a`
  - `/health` (rewritten from `/health/service-a`)

## Best Practices

1. **Always verify service health before port-forwarding**
2. **Use foreground port-forward for debugging**
3. **Clean up background processes when done**
4. **Consider using Gateway API for production access**
5. **Use unique ports for different services to avoid conflicts**
6. **Implement health checks in your applications**

## Quick Test Commands

```bash
# Complete test sequence
pkill -f "port-forward.*9999" || true
kubectl port-forward svc/service-a 9999:8080 &
sleep 3
curl http://localhost:9999/api/service-a/hello
kill %1
```

The final success in your output shows the service is working correctly - the issue was purely with the port-forward timing and process management.