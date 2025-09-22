#!/bin/bash

# Use EnvoyFilter approach for access logging (advanced method)
# This replicates the exact EnvoyProxy configuration in Istio

set -e

echo "Setting up access logging using EnvoyFilter approach..."

# Step 1: Remove any existing Telemetry API configurations
echo "1. Removing existing Telemetry configurations (if any)..."
kubectl delete telemetry istio-access-logging -n istio-system --ignore-not-found

# Step 2: Apply the EnvoyFilter for access logging
echo "2. Applying EnvoyFilter for access logging..."
kubectl apply -f gateway/istio/06-envoyfilter-access-logging.yaml

# Step 3: Restart components to pick up new configuration
echo "3. Restarting ingress gateway..."
kubectl rollout restart deployment/istio-ingressgateway -n istio-system
kubectl rollout status deployment/istio-ingressgateway -n istio-system --timeout=300s

echo "4. Restarting application pods for sidecar logging..."
kubectl rollout restart deployment/service-a deployment/service-b -n default
kubectl rollout status deployment/service-a -n default --timeout=300s
kubectl rollout status deployment/service-b -n default --timeout=300s

echo "✅ EnvoyFilter access logging setup complete!"
echo ""
echo "This approach provides:"
echo "  • JSON logs to stdout (same format as your EnvoyProxy config)"
echo "  • Human-readable logs to stderr"
echo "  • Exact replication of gateway/observability/envoy-observability.yaml"
echo ""
echo "To view logs:"
echo "  kubectl logs -f deployment/istio-ingressgateway -n istio-system"
echo "  kubectl logs -f deployment/service-a -c istio-proxy"
echo ""
echo "Generate traffic to see the access logs!"