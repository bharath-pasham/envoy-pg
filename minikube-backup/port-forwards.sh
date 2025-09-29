#!/bin/bash

# Port-forward recreation script
# Based on the port-forwards that were active when backup was created

echo "Setting up port-forwards..."

# Kill any existing port-forwards to avoid conflicts
echo "Killing existing port-forwards..."
pkill -f "kubectl.*port-forward" || true

# Wait a moment for processes to terminate
sleep 2

# Start port-forwards in background
echo "Starting port-forwards..."

# Prometheus (observability monitoring)
echo "Port-forwarding Prometheus: http://localhost:9090"
kubectl port-forward -n observability svc/prometheus 9090:9090 &
PROMETHEUS_PID=$!

# Grafana (observability dashboards)
echo "Port-forwarding Grafana: http://localhost:3000"
kubectl port-forward -n observability svc/grafana 3000:3000 &
GRAFANA_PID=$!

# Istio Gateway (main application gateway)
echo "Port-forwarding Istio Gateway: http://localhost:8080"
kubectl port-forward svc/istio-demo-gateway-istio 8080:80 &
GATEWAY_PID=$!

# Wait a moment for port-forwards to establish
sleep 3

echo ""
echo "Port-forwards established:"
echo "  Prometheus:    http://localhost:9090"
echo "  Grafana:       http://localhost:3000"
echo "  Istio Gateway: http://localhost:8080"
echo ""
echo "Process IDs:"
echo "  Prometheus: $PROMETHEUS_PID"
echo "  Grafana: $GRAFANA_PID"
echo "  Gateway: $GATEWAY_PID"
echo ""
echo "To kill all port-forwards:"
echo "  pkill -f 'kubectl.*port-forward'"
echo ""
echo "Port-forwards will run in background. Press Ctrl+C to exit this script (port-forwards will continue)."

# Keep script running so user can see any errors
wait