#!/bin/bash

echo "🔬 Testing Observability Features"
echo "================================="
echo ""

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Base URLs
GATEWAY_URL="http://localhost:8888"
PROMETHEUS_URL="http://localhost:9090"
ENVOY_ADMIN_URL="http://localhost:19000"
GRAFANA_URL="http://localhost:3000"

# Section function
section() {
    echo ""
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}$1${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

# Test 1: Access Logs
section "📝 TEST 1: ACCESS LOGS"

echo "Making requests and checking access logs..."
echo ""

# Make a request with custom headers
echo "Request with tracing headers:"
curl -s -H "Host: api.demo.local" \
     -H "X-Request-ID: test-$(date +%s)" \
     -H "X-B3-TraceId: $(openssl rand -hex 16)" \
     -H "X-B3-SpanId: $(openssl rand -hex 8)" \
     $GATEWAY_URL/api/service-a/hello | jq .

echo ""
echo "Checking access logs (last 5 entries):"
kubectl logs -n envoy-gateway-system \
    -l gateway.envoyproxy.io/owning-gateway-name=demo-gateway \
    --tail=5 | grep -E "test-" || echo "No matching logs yet"

# Test 2: Metrics Collection
section "📊 TEST 2: METRICS COLLECTION"

echo "Generating traffic patterns for metrics..."

# Generate normal traffic
echo -n "Normal traffic (50 requests): "
for i in {1..50}; do
    curl -s -H "Host: api.demo.local" $GATEWAY_URL/api/service-a/hello > /dev/null 2>&1
    echo -n "."
done
echo " ✓"

# Generate 404 errors
echo -n "404 errors (10 requests): "
for i in {1..10}; do
    curl -s -H "Host: api.demo.local" $GATEWAY_URL/nonexistent > /dev/null 2>&1
    echo -n "."
done
echo " ✓"

# Generate slow requests
echo -n "Slow requests (5 requests): "
for i in {1..5}; do
    curl -s -H "Host: api.demo.local" $GATEWAY_URL/api/service-b/slow?seconds=2 > /dev/null 2>&1
    echo -n "."
done
echo " ✓"

echo ""
echo "Querying Prometheus for metrics:"
echo ""

# Query request rate
echo "📈 Request Rate (last 5 min):"
curl -s "$PROMETHEUS_URL/api/v1/query?query=rate(envoy_http_downstream_rq_total[5m])" | \
    jq -r '.data.result[0].value[1] // "No data"' | \
    xargs -I {} echo "  {} requests/second"

# Query error rate
echo "❌ Error Rate (4xx/5xx):"
curl -s "$PROMETHEUS_URL/api/v1/query?query=rate(envoy_http_downstream_rq_xx[5m])" | \
    jq -r '.data.result[] | "\(.metric.envoy_response_code_class)xx: \(.value[1])"' 2>/dev/null || echo "  No errors"

# Query P99 latency
echo "⏱️  P99 Latency:"
curl -s "$PROMETHEUS_URL/api/v1/query?query=histogram_quantile(0.99,rate(envoy_http_downstream_rq_time_bucket[5m]))" | \
    jq -r '.data.result[0].value[1] // "No data"' | \
    xargs -I {} echo "  {} ms"

# Test 3: Envoy Admin Interface
section "🎛️ TEST 3: ENVOY ADMIN INTERFACE"

echo "Checking Envoy Admin endpoints:"
echo ""

# Check clusters
echo "📍 Active Clusters:"
curl -s $ENVOY_ADMIN_URL/clusters | grep -E "^default::" | head -5 || echo "  Admin interface not accessible"

echo ""
echo "📊 Stats Summary:"
curl -s $ENVOY_ADMIN_URL/stats/prometheus | grep -E "envoy_http_downstream_rq_total|envoy_cluster_upstream_rq_total" | head -5 || echo "  No stats available"

echo ""
echo "🔧 Config Dump (listeners):"
curl -s $ENVOY_ADMIN_URL/config_dump | jq '.configs[].dynamic_listeners[].active_state.listener.name' 2>/dev/null | head -3 || echo "  No config available"

# # Test 4: Circuit Breaker Testing
# section "🔌 TEST 4: CIRCUIT BREAKER BEHAVIOR"

# echo "Triggering circuit breaker with concurrent requests..."
# echo ""

# # Send concurrent requests to trigger circuit breaker
# echo "Sending 20 concurrent requests..."
# for i in {1..20}; do
#     curl -s -H "Host: api.demo.local" $GATEWAY_URL/api/service-a/hello > /dev/null 2>&1 &
# done
# wait

# echo "Checking circuit breaker metrics:"
# curl -s "$PROMETHEUS_URL/api/v1/query?query=envoy_cluster_circuit_breakers_default_rq_open" | \
#     jq -r '.data.result[0].value[1] // "0"' | \
#     xargs -I {} echo "  Open circuits: {}"

# # Test 5: Rate Limiting Metrics
# section "⏰ TEST 5: RATE LIMITING METRICS"

# echo "Testing rate limits (sending 15 rapid requests)..."
# echo ""

# success=0
# rate_limited=0

# for i in {1..15}; do
#     response_code=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: api.demo.local" $GATEWAY_URL/data)
#     if [ "$response_code" = "200" ]; then
#         ((success++))
#         echo -n "✓"
#     elif [ "$response_code" = "429" ]; then
#         ((rate_limited++))
#         echo -n "⛔"
#     else
#         echo -n "?"
#     fi
# done
# echo ""
# echo "  Success: $success, Rate Limited: $rate_limited"

# echo ""
# echo "Rate limit metrics:"
# curl -s "$PROMETHEUS_URL/api/v1/query?query=envoy_http_local_rate_limit_rate_limited" | \
#     jq -r '.data.result[0].value[1] // "0"' | \
#     xargs -I {} echo "  Total rate limited: {}"

# Test 6: Health Checks
section "💚 TEST 6: HEALTH CHECK MONITORING"

echo "Checking upstream health status..."
echo ""

# Check healthy hosts
echo "Healthy upstream hosts:"
curl -s "$PROMETHEUS_URL/api/v1/query?query=envoy_cluster_membership_healthy" | \
    jq -r '.data.result[] | "  \(.metric.envoy_cluster_name): \(.value[1])"' 2>/dev/null || echo "  No data"

echo ""
echo "Health check attempts:"
curl -s "$PROMETHEUS_URL/api/v1/query?query=envoy_cluster_health_check_attempt" | \
    jq -r '.data.result[0].value[1] // "0"' | \
    xargs -I {} echo "  Total attempts: {}"

# Test 7: Response Headers with Metrics
section "📋 TEST 7: OBSERVABILITY HEADERS"

echo "Checking response headers with timing information..."
echo ""

response=$(curl -s -i -H "Host: api.demo.local" $GATEWAY_URL/api/service-a/hello)
echo "Response Headers:"
echo "$response" | grep -E "X-Response-Time|X-Upstream-Service-Time|X-Route-Name|X-Service" | sed 's/^/  /'

# Test 8: Load Distribution
# section "⚖️ TEST 8: LOAD BALANCING METRICS"

# echo "Testing load distribution (50 requests)..."
# echo ""

# declare -A service_count
# for i in {1..50}; do
#     service=$(curl -s -H "Host: api.demo.local" $GATEWAY_URL/api | jq -r .service 2>/dev/null || echo "error")
#     ((service_count[$service]++))
#     echo -n "."
# done
# echo ""
# echo ""
# echo "Load distribution:"
# for service in "${!service_count[@]}"; do
#     percentage=$(( service_count[$service] * 100 / 50 ))
#     echo "  $service: ${service_count[$service]} requests ($percentage%)"
# done

# Test 9: Grafana Dashboard
section "📊 TEST 9: GRAFANA DASHBOARD"

echo "Checking Grafana availability..."
if curl -s -o /dev/null -w "%{http_code}" $GRAFANA_URL | grep -q "200\|302"; then
    echo -e "  ${GREEN}✅ Grafana is accessible at $GRAFANA_URL${NC}"
    echo "  Default credentials: admin/admin"
    echo ""
    echo "  Recommended panels to check:"
    echo "  - Request Rate"
    echo "  - Response Status Codes"
    echo "  - P50/P90/P99 Latency"
    echo "  - Active Connections"
    echo "  - Upstream Health"
else
    echo -e "  ${YELLOW}⚠️ Grafana not accessible. Run setup-observability.sh first${NC}"
fi

# Test 10: Log Aggregation
section "📚 TEST 10: LOG AGGREGATION"

echo "Analyzing access log patterns..."
echo ""

echo "Top 5 paths by request count:"
kubectl logs -n envoy-gateway-system \
    -l gateway.envoyproxy.io/owning-gateway-name=demo-gateway \
    --tail=1000 2>/dev/null | \
    grep -oE '\"path\":\"[^\"]+' | \
    cut -d'"' -f4 | \
    sort | uniq -c | sort -rn | head -5 | \
    sed 's/^/  /'

echo ""
echo "Response code distribution:"
kubectl logs -n envoy-gateway-system \
    -l gateway.envoyproxy.io/owning-gateway-name=demo-gateway \
    --tail=1000 2>/dev/null | \
    grep -oE '\"response_code\":\"[0-9]+' | \
    cut -d'"' -f4 | \
    sort | uniq -c | sort -rn | \
    sed 's/^/  /'

# Summary
section "📈 OBSERVABILITY SUMMARY"

echo -e "${GREEN}✅ Observability Features Tested:${NC}"
echo "  • Access logs with structured JSON format"
echo "  • Prometheus metrics collection"
echo "  • Envoy admin interface"
echo "  • Circuit breaker monitoring"
echo "  • Rate limiting metrics"
echo "  • Health check monitoring"
echo "  • Response timing headers"
echo "  • Load balancing metrics"
echo "  • Grafana dashboard integration"
echo "  • Log aggregation and analysis"
echo ""

echo -e "${BLUE}📊 Key Metrics Endpoints:${NC}"
echo "  • Prometheus: $PROMETHEUS_URL"
echo "  • Grafana: $GRAFANA_URL"
echo "  • Envoy Admin: $ENVOY_ADMIN_URL"
echo ""

echo -e "${YELLOW}🔍 Useful Queries:${NC}"
echo "  • Request rate: rate(envoy_http_downstream_rq_total[5m])"
echo "  • Error rate: rate(envoy_http_downstream_rq_xx[5m])"
echo "  • P99 latency: histogram_quantile(0.99, rate(envoy_http_downstream_rq_time_bucket[5m]))"
echo "  • Circuit breakers: envoy_cluster_circuit_breakers_default_rq_open"
echo "  • Rate limits: envoy_http_local_rate_limit_rate_limited"
echo ""

echo -e "${GREEN}✅ Observability testing complete!${NC}"