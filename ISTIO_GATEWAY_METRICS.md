# Istio Gateway Request Duration Metrics

## Overview
The `istio_gateway_request_duration_ms` metric tracks request durations through Istio gateways. This document provides queries for calculating various percentiles.

## Percentile Queries

### P50 (Median)
```promql
histogram_quantile(0.50, rate(istio_gateway_request_duration_ms_bucket[5m]))
```

### P75 (75th Percentile)
```promql
histogram_quantile(0.75, rate(istio_gateway_request_duration_ms_bucket[5m]))
```

### P90 (90th Percentile)
```promql
histogram_quantile(0.90, rate(istio_gateway_request_duration_ms_bucket[5m]))
```

### P95 (95th Percentile)
```promql
histogram_quantile(0.95, rate(istio_gateway_request_duration_ms_bucket[5m]))
```

### P99 (99th Percentile)
```promql
histogram_quantile(0.99, rate(istio_gateway_request_duration_ms_bucket[5m]))
```

## Multi-Percentile Query
Get all percentiles in a single query:
```promql
histogram_quantile(0.50, rate(istio_gateway_request_duration_ms_bucket[5m])) or
histogram_quantile(0.75, rate(istio_gateway_request_duration_ms_bucket[5m])) or
histogram_quantile(0.90, rate(istio_gateway_request_duration_ms_bucket[5m])) or
histogram_quantile(0.95, rate(istio_gateway_request_duration_ms_bucket[5m])) or
histogram_quantile(0.99, rate(istio_gateway_request_duration_ms_bucket[5m]))
```

## Filtering by Labels
Add label filters as needed:
```promql
histogram_quantile(0.95,
  rate(istio_gateway_request_duration_ms_bucket{
    source_app="your-app",
    destination_service_name="your-service"
  }[5m])
)
```

## Time Range Variations
- Last 1 minute: `[1m]`
- Last 15 minutes: `[15m]`
- Last 1 hour: `[1h]`

## Notes
- The `rate()` function calculates per-second rate over the time window
- Adjust the time window `[5m]` based on your data resolution needs
- Higher percentiles (P99) may be less stable with smaller time windows