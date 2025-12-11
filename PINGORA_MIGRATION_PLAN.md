# Pingora Migration Plan

Future migration from Caddy to Pingora-based proxy for AlternateFutures infrastructure.

## Current State

**Proxy:** Caddy 2.x with Cloudflare DNS plugin
**Language:** Go
**Features:** DNS-01 Let's Encrypt, auto-renewal, reverse proxy
**Resource Usage:** ~30MB RAM, 0.5 CPU
**Deployment:** Akash Network

## Target State

**Proxy:** Pingap (Pingora-based) or custom Pingora implementation
**Language:** Rust
**Features:** DNS-01 Let's Encrypt, auto-renewal, reverse proxy, advanced load balancing
**Expected Resource Usage:** ~10-15MB RAM, 0.2 CPU

---

## Migration Triggers

Start migration planning when **ANY** of these thresholds are met:

### Traffic Thresholds

| Metric | Current | Migration Trigger | Notes |
|--------|---------|-------------------|-------|
| Requests/second | <10 | >1,000 RPS sustained | P95 latency matters at scale |
| Monthly requests | <1M | >100M/month | Cost optimization becomes significant |
| Concurrent connections | <100 | >10,000 | Connection pooling benefits |
| Bandwidth | <1 TB/mo | >50 TB/month | Memory efficiency critical |

### Performance Thresholds

| Metric | Current | Migration Trigger | Notes |
|--------|---------|-------------------|-------|
| P50 latency | N/A | >50ms | Caddy overhead noticeable |
| P99 latency | N/A | >200ms | Tail latency affecting UX |
| CPU usage | <10% | >70% sustained | Vertical scaling limit |
| Memory usage | <100MB | >500MB | Container resource pressure |

### Cost Thresholds

| Metric | Current | Migration Trigger | Notes |
|--------|---------|-------------------|-------|
| Proxy compute cost | ~$5/mo | >$500/month | ROI on engineering time |
| SSL cert operations | Minimal | Rate limited by LE | Need cert caching layer |

### Feature Triggers

Migrate if we need features Caddy doesn't provide well:

- [ ] Custom request/response transformation in hot path
- [ ] WebAssembly plugin system
- [ ] gRPC-native load balancing
- [ ] Custom connection pooling strategies
- [ ] Kernel bypass networking (io_uring, DPDK)
- [ ] Blue-green deployments with traffic splitting
- [ ] Circuit breaker patterns at proxy level
- [ ] Request coalescing/deduplication

---

## Migration Phases

### Phase 0: Monitoring (Now)

**Timeline:** Ongoing
**Effort:** 2 hours setup

1. Add Prometheus metrics to Caddy
2. Set up Grafana dashboards for:
   - Request rate
   - Latency percentiles (P50, P95, P99)
   - Error rates
   - Resource usage
3. Create alerts for migration trigger thresholds

```yaml
# Add to Caddyfile
{
    servers {
        metrics
    }
}

:9180 {
    metrics /metrics
}
```

### Phase 1: Evaluation (When triggered)

**Timeline:** 2 weeks
**Effort:** 40 hours

1. **Benchmark current Caddy setup**
   - Load test with k6 or wrk
   - Document baseline metrics

2. **Evaluate Pingora options**
   - [Pingap](https://github.com/vicanso/pingap) - Ready to use
   - [Pingora Proxy Manager](https://github.com/DDULDDUCK/pingora-proxy-manager) - Web UI
   - Custom Pingora implementation

3. **Proof of Concept**
   - Deploy Pingap alongside Caddy
   - Compare performance on staging traffic
   - Test DNS-01 certificate provisioning

4. **Decision checkpoint**
   - If Pingap meets needs → Phase 2a
   - If custom needed → Phase 2b
   - If benefits marginal → Defer migration

### Phase 2a: Pingap Migration

**Timeline:** 1 week
**Effort:** 20 hours

1. **Configuration translation**
   ```toml
   # pingap.toml equivalent of our Caddyfile
   [upstreams.auth]
   addrs = ["ubsm31q4ol97b1pi5l06iognug.ingress.europlots.com:443"]

   [locations.auth]
   upstream = "auth"
   host = "auth.alternatefutures.ai"

   [certificates]
   acme_provider = "cloudflare"
   dns_provider_token = "${CF_API_TOKEN}"
   domains = ["auth.alternatefutures.ai", "api.alternatefutures.ai", "app.alternatefutures.ai"]
   ```

2. **Docker image**
   ```dockerfile
   FROM rust:alpine AS builder
   RUN cargo install pingap

   FROM alpine:latest
   COPY --from=builder /usr/local/cargo/bin/pingap /usr/local/bin/
   COPY pingap.toml /etc/pingap/
   CMD ["pingap", "-c", "/etc/pingap/pingap.toml"]
   ```

3. **Staged rollout**
   - Deploy to Akash alongside Caddy
   - Route 1% traffic via DNS weight
   - Gradually increase to 100%
   - Decommission Caddy

### Phase 2b: Custom Pingora Implementation

**Timeline:** 4-6 weeks
**Effort:** 160+ hours
**Requires:** Rust developer

1. **Project setup**
   ```rust
   // Cargo.toml
   [dependencies]
   pingora = "0.1"
   pingora-core = "0.1"
   pingora-proxy = "0.1"
   ```

2. **Core proxy implementation**
   ```rust
   use pingora::prelude::*;

   pub struct AlternateFuturesProxy {
       // Custom logic here
   }

   impl ProxyHttp for AlternateFuturesProxy {
       // Request/response handling
   }
   ```

3. **ACME integration**
   - Integrate with `acme-lib` or similar
   - Implement Cloudflare DNS-01 challenge
   - Certificate storage and rotation

4. **Testing & deployment**
   - Unit tests, integration tests
   - Load testing
   - Staged rollout (same as 2a)

---

## Technical Requirements

### For Pingap (Phase 2a)

- [ ] Rust runtime compatible container
- [ ] Certbot or ACME client
- [ ] Cloudflare API token (existing)
- [ ] Persistent storage for certificates

### For Custom Pingora (Phase 2b)

- [ ] Rust developer (hire or train)
- [ ] CI/CD for Rust builds
- [ ] All of Phase 2a requirements
- [ ] Extended testing infrastructure

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| DNS-01 integration issues | Medium | High | Test extensively in staging |
| Performance regression | Low | Medium | A/B test before full rollout |
| Operational complexity | Medium | Medium | Document runbooks |
| Rust expertise gap | High | High | Use Pingap, not custom |
| Certificate provisioning failure | Medium | Critical | Keep Caddy as fallback |

---

## Rollback Plan

1. Keep Caddy deployment YAML archived
2. Maintain Caddy Docker image in GHCR
3. DNS TTL set to 5 minutes for quick failover
4. Document rollback procedure:
   ```bash
   # Emergency rollback
   kubectl apply -f caddy-deployment.yaml  # or Akash equivalent
   # Update DNS to point to Caddy instance
   ```

---

## Decision Log

| Date | Decision | Rationale |
|------|----------|-----------|
| 2025-12-11 | Use Caddy initially | Simple, proven DNS-01 support, fast deployment |
| TBD | Evaluate Pingora | When traffic thresholds met |

---

## Monitoring Checklist

Before any migration decision, ensure we have data on:

- [ ] 30-day request volume trend
- [ ] P50/P95/P99 latency baseline
- [ ] Peak concurrent connections
- [ ] CPU/memory usage patterns
- [ ] Error rates by type
- [ ] Certificate renewal success rate
- [ ] Monthly infrastructure cost

---

## References

- [Pingora GitHub](https://github.com/cloudflare/pingora)
- [Pingap - Production-ready Pingora proxy](https://github.com/vicanso/pingap)
- [Pingora Proxy Manager](https://github.com/DDULDDUCK/pingora-proxy-manager)
- [Cloudflare Pingora Blog Post](https://blog.cloudflare.com/how-we-built-pingora-the-proxy-that-connects-cloudflare-to-the-internet/)
- [Caddy vs alternatives benchmark](https://www.loggly.com/blog/benchmarking-5-popular-load-balancers-nginx-haproxy-envoy-traefik-and-alb/)
