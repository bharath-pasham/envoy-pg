#!/bin/bash

echo "🔭 Setting up Observability for Envoy Gateway"
echo "============================================="
echo ""

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Function to wait for deployment
wait_for_deployment() {
    local namespace=$1
    local deployment=$2
    echo -n "Waiting for $deployment in $namespace..."
    kubectl wait --for=condition=available --timeout=120s deployment/$deployment -n $namespace
    echo -e " ${GREEN}✓${NC}"
}

# Step 1: Deploy Observability Stack
echo -e "${BLUE}📦 Step 1: Deploying Observability Stack${NC}"
kubectl apply -f observability-stack.yaml

# Wait for Prometheus and Grafana
wait_for_deployment observability prometheus
wait_for_deployment observability grafana

echo -e "${GREEN}✅ Observability stack deployed${NC}"
echo ""

# Step 2: Configure Envoy for Observability
echo -e "${BLUE}🔧 Step 2: Configuring Envoy Gateway for Observability${NC}"
kubectl apply -f envoy-observability.yaml
kubectl apply -f observability-routes.yaml
sleep 5
echo -e "${GREEN}✅ Envoy observability configured${NC}"
echo ""

# Step 3: Set up Port Forwarding
echo -e "${BLUE}🌐 Step 3: Setting up Port Forwarding${NC}"

# Kill existing port-forwards
pkill -f "port-forward.*prometheus" 2>/dev/null
pkill -f "port-forward.*grafana" 2>/dev/null
pkill -f "port-forward.*envoy-gateway" 2>/dev/null

# Start port forwarding
echo "Starting Prometheus port-forward (9090)..."
kubectl port-forward -n observability svc/prometheus 9090:9090 > /dev/null 2>&1 &
PROM_PID=$!

echo "Starting Grafana port-forward (3000)..."
kubectl port-forward -n observability svc/grafana 3000:3000 > /dev/null 2>&1 &
GRAFANA_PID=$!

echo "Starting Envoy Admin port-forward (19000)..."
# Get the Envoy pod name
ENVOY_POD=$(kubectl get pods -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-name=demo-gateway -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$ENVOY_POD" ]; then
    kubectl port-forward -n envoy-gateway-system pod/$ENVOY_POD 19000:19000 > /dev/null 2>&1 &
    ENVOY_ADMIN_PID=$!
    echo -e "${GREEN}✅ Port forwarding established${NC}"
else
    echo -e "${YELLOW}⚠️  No Envoy pod found for admin interface${NC}"
fi
echo ""

# Step 4: Display Access Information
echo -e "${BLUE}📊 Step 4: Access Information${NC}"
echo "=================================="
echo -e "${GREEN}Prometheus:${NC} http://localhost:9090"
echo -e "${GREEN}Grafana:${NC} http://localhost:3000 (admin/admin)"
echo -e "${GREEN}Envoy Admin:${NC} http://localhost:19000"
echo ""

# Step 5: Generate Sample Traffic
echo -e "${BLUE}🚦 Step 5: Generating Sample Traffic for Metrics${NC}"
echo "Sending 100 requests to populate metrics..."

# Function to send traffic
send_traffic() {
    local endpoint=$1
    local count=$2
    for i in $(seq 1 $count); do
        curl -s -H "Host: api.demo.local" http://localhost:8888$endpoint > /dev/null 2>&1
        echo -n "."
    done
}

# Send various types of traffic
send_traffic "/api/service-a/hello" 20
send_traffic "/api/service-b/hello" 20
send_traffic "/health/service-a" 10
send_traffic "/metrics" 10
send_traffic "/api/v1/test" 20
send_traffic "/experiment" 20

echo ""
echo -e "${GREEN}✅ Sample traffic generated${NC}"
echo ""

# Step 6: Quick Metrics Check
echo -e "${BLUE}📈 Step 6: Quick Metrics Verification${NC}"
echo "======================================"

# Check Prometheus targets
echo "Checking Prometheus targets..."
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, health: .health}' 2>/dev/null || echo "Prometheus not ready yet"
echo ""

# Check for Envoy metrics
echo "Sample Envoy metrics:"
curl -s http://localhost:9090/api/v1/query?query=envoy_http_downstream_rq_total | jq '.data.result[0].value[1]' 2>/dev/null || echo "No metrics yet"
echo ""

# Step 7: Import Grafana Dashboard
echo -e "${BLUE}📊 Step 7: Grafana Dashboard Setup${NC}"
echo "==================================="
echo "To import the dashboard:"
echo "1. Open http://localhost:3000 (admin/admin)"
echo "2. Go to Dashboards → Import"
echo "3. Upload the grafana-envoy-dashboard.json file"
echo "4. Select 'Prometheus' as the data source"
echo ""

# Step 8: Useful Commands
echo -e "${BLUE}🔍 Useful Observability Commands${NC}"
echo "================================="
cat << 'EOF'
# View Envoy configuration
curl -s http://localhost:19000/config_dump | jq .

# View Envoy clusters
curl -s http://localhost:19000/clusters

# View Envoy stats
curl -s http://localhost:19000/stats/prometheus

# View access logs
kubectl logs -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-name=demo-gateway -f

# Query Prometheus
curl -s http://localhost:9090/api/v1/query?query=envoy_http_downstream_rq_total

# Get rate of requests
curl -s http://localhost:9090/api/v1/query?query='rate(envoy_http_downstream_rq_total[5m])'

# Get P99 latency
curl -s http://localhost:9090/api/v1/query?query='histogram_quantile(0.99, rate(envoy_http_downstream_rq_time_bucket[5m]))'

# Check circuit breaker status
curl -s http://localhost:9090/api/v1/query?query=envoy_cluster_circuit_breakers_default_rq_open

# View rate limit metrics
curl -s http://localhost:9090/api/v1/query?query=envoy_http_local_rate_limit_rate_limited
EOF
echo ""

# Step 9: Cleanup function
echo -e "${YELLOW}To stop port-forwarding, run:${NC}"
echo "kill $PROM_PID $GRAFANA_PID ${ENVOY_ADMIN_PID:-0}"
echo ""

echo -e "${GREEN}✅ Observability setup complete!${NC}"
echo ""
echo "Next steps:"
echo "1. Open Grafana at http://localhost:3000"
echo "2. Explore Prometheus at http://localhost:9090"
echo "3. Check Envoy Admin at http://localhost:19000"
echo "4. Run test-observability.sh to see metrics in action"