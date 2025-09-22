#!/bin/bash

# Install Istio with JSON access logging pre-configured
# This script installs Istio with the same JSON access log format as your Envoy Gateway setup

set -e

ISTIO_VERSION="1.22.3"

echo "Installing Istio $ISTIO_VERSION with JSON access logging..."

# Download Istio if not already present
if ! command -v istioctl &> /dev/null; then
    echo "Downloading Istio $ISTIO_VERSION..."
    curl -L https://istio.io/downloadIstio | ISTIO_VERSION=$ISTIO_VERSION sh -
    export PATH="$PWD/istio-$ISTIO_VERSION/bin:$PATH"
fi

# Create IstioOperator configuration with JSON access logging
cat > /tmp/istio-operator-with-logging.yaml << 'EOF'
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
spec:
  meshConfig:
    # Enable JSON encoding for access logs
    accessLogEncoding: JSON
    # Define the exact JSON format matching your Envoy Gateway configuration
    accessLogFormat: |
      {
        "timestamp": "%START_TIME%",
        "method": "%REQ(:METHOD)%",
        "path": "%REQ(X-ENVOY-ORIGINAL-PATH?:PATH)%",
        "protocol": "%PROTOCOL%",
        "response_code": "%RESPONSE_CODE%",
        "response_flags": "%RESPONSE_FLAGS%",
        "bytes_received": "%BYTES_RECEIVED%",
        "bytes_sent": "%BYTES_SENT%",
        "duration": "%DURATION%",
        "upstream_service_time": "%RESP(X-ENVOY-UPSTREAM-SERVICE-TIME)%",
        "x_forwarded_for": "%REQ(X-FORWARDED-FOR)%",
        "user_agent": "%REQ(USER-AGENT)%",
        "request_id": "%REQ(X-REQUEST-ID)%",
        "authority": "%REQ(:AUTHORITY)%",
        "upstream_host": "%UPSTREAM_HOST%",
        "upstream_cluster": "%UPSTREAM_CLUSTER%",
        "downstream_remote_address": "%DOWNSTREAM_REMOTE_ADDRESS%",
        "downstream_local_address": "%DOWNSTREAM_LOCAL_ADDRESS%",
        "route_name": "%ROUTE_NAME%"
      }
    defaultConfig:
      # Enable proxy stats for observability
      proxyStatsMatcher:
        inclusionRegexps:
        - ".*outlier_detection.*"
        - ".*circuit_breakers.*"
        - ".*upstream_rq_retry.*"
        - ".*upstream_rq_pending.*"
  values:
    global:
      proxy:
        logLevel: warning
    pilot:
      env:
        EXTERNAL_ISTIOD: false
EOF

# Install Istio with the configuration
echo "Installing Istio with JSON access logging configuration..."
istioctl install -f /tmp/istio-operator-with-logging.yaml -y

# Clean up
rm /tmp/istio-operator-with-logging.yaml

# Verify installation
echo "Verifying Istio installation..."
istioctl verify-install

# Enable sidecar injection for default namespace
echo "Enabling sidecar injection for default namespace..."
kubectl label namespace default istio-injection=enabled --overwrite

# Apply the Telemetry resource to enable access logging
echo "Applying Telemetry configuration..."
kubectl apply -f - << 'EOF'
apiVersion: telemetry.istio.io/v1beta1
kind: Telemetry
metadata:
  name: istio-access-logging
  namespace: istio-system
spec:
  accessLogging:
  - providers:
    - name: envoy
EOF

echo "✅ Istio installation with JSON access logging complete!"
echo ""
echo "Next steps:"
echo "1. Apply your Istio gateway configuration: kubectl apply -f gateway/istio/"
echo "2. Restart your application pods to inject sidecars: kubectl rollout restart deployment/service-a deployment/service-b"
echo "3. Generate traffic and check logs: kubectl logs -f deployment/istio-ingressgateway -n istio-system"
echo ""
echo "Your access logs will now be in the same JSON format as your Envoy Gateway configuration!"