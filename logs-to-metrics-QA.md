# Gateway Logs to Metrics - Requirements Q&A Document

## 1. Technical Environment

**Q: What's your current infrastructure setup? Are you running on Kubernetes (I see cluster.local references), cloud-native, or hybrid?**  
**A:** We are running Kubernetes and it's cloud native.

**Q: What's your expected log volume? (requests/second, GB/day)**  
**A:** Expected low volume, less than 100 requests per second. Not sure on the gigabytes per day.

**Q: Are these logs currently being written to files, stdout, or already streaming somewhere?**  
**A:** We don't have any logs being written for now, but they will be written to stdout.

## 2. Metrics Requirements

**Q: What types of metrics are most important to you? (Request rate/throughput, Latency percentiles, Error rates, Service-specific metrics, Business metrics)**  
**A:** The most important metrics would be:
- Request rate
- Latency percentiles
- Error rates  
- Service-specific metrics to a certain extent
- Business metrics are not necessary

**Q: What latency requirements do you have for metrics availability? (Near real-time, Near-time, Batch)**  
**A:** Batch (hourly/daily) would be fine.

## 3. Existing Tools & Constraints

**Q: Do you already have any observability stack components in place? (Prometheus, Elasticsearch, Grafana, Datadog, etc.)**  
**A:** We have Datadog. We don't have anything else.

**Q: Are there any technology preferences or constraints? (open source only, specific cloud vendor, budget considerations)**  
**A:** We don't have any technology preference. Budget would be approximately €100,000 per year.

**Q: Do you need to retain raw logs alongside metrics, or can metrics replace log storage for certain use cases?**  
**A:** We don't need to retain the raw logs. We are only interested in the metrics.

## 4. Scale & Growth

**Q: How many services and routes do you expect to monitor?**  
**A:** Approximately 10 services and in total 100 routes.

**Q: Do you need multi-tenancy or different access levels for metrics?**  
**A:** We do need multi-tenancy, but it won't matter for different levels of metrics. All tenants will get exactly the same metrics from the service.

---

**Document Version:** 1.0  
**Date:** September 23, 2025  
**Status:** Requirements Confirmed