#!/bin/bash

# Setup script for Istio JSON access logging
# This configures Istio to produce the same JSON access logs as your Envoy Gateway setup

set -e

echo "Setting up Istio JSON access logging..."

# Step 1: Apply the Telemetry resource to enable access logging
echo "1. Enabling access logging via Telemetry resource..."
kubectl apply -f gateway/istio/05-telemetry.yaml

# Step 2: Update the mesh configuration to use JSON format
echo "2. Configuring JSON access log format..."

# Check if Istio is installed and get the current mesh config
if kubectl get configmap istio -n istio-system >/dev/null 2>&1; then
    echo "Found existing Istio installation. Updating mesh configuration..."
    
    # Apply the mesh config patch
    kubectl patch configmap istio -n istio-system --patch-file gateway/istio/mesh-config-patch.yaml
    
    echo "Mesh configuration updated. Restarting Istio control plane..."
    kubectl rollout restart deployment/istiod -n istio-system
    
    echo "Waiting for Istio control plane to be ready..."
    kubectl rollout status deployment/istiod -n istio-system --timeout=300s
    
else
    echo "No existing Istio installation found. Please install Istio first with:"
    echo "istioctl install --set meshConfig.accessLogEncoding=JSON --set meshConfig.accessLogFormat='...' -y"
    exit 1
fi

# Step 3: Restart gateway and application pods to pick up new config
echo "3. Restarting ingress gateway to pick up new configuration..."
kubectl rollout restart deployment/istio-ingressgateway -n istio-system
kubectl rollout status deployment/istio-ingressgateway -n istio-system --timeout=300s

echo "4. Restarting application pods to pick up new sidecar configuration..."
kubectl rollout restart deployment/service-a deployment/service-b -n default
kubectl rollout status deployment/service-a -n default --timeout=300s
kubectl rollout status deployment/service-b -n default --timeout=300s

echo "✅ Istio JSON access logging setup complete!"
echo ""
echo "To view access logs:"
echo "  # For ingress gateway logs:"
echo "  kubectl logs -f deployment/istio-ingressgateway -n istio-system"
echo ""
echo "  # For application sidecar logs:"
echo "  kubectl logs -f deployment/service-a -c istio-proxy"
echo "  kubectl logs -f deployment/service-b -c istio-proxy"
echo ""
echo "Generate some traffic and you should see JSON formatted access logs!"