# AlternateFutures SSL Proxy (Pingap + etcd)

High-performance SSL termination proxy with **dynamic routing** for AlternateFutures services running on Akash Network. Built on Cloudflare's Pingora framework with etcd backend for hot-reload configuration.

## Current Deployment

| Field | Value |
|-------|-------|
| **DSEQ** | 24576255 |
| **Provider** | Europlots (`akash162gym3szcy9d993gs3tyu0mg2ewcjacen9nwsu`) |
| **Image (Static)** | `ghcr.io/alternatefutures/infrastructure-proxy-pingap:main` |
| **Image (Dynamic)** | `ghcr.io/alternatefutures/infrastructure-proxy-pingap:etcd` |
| **Status** | Running |

## Overview

This proxy solves two key challenges with Akash Network:

1. **SSL for custom domains**: Akash providers use wildcard certificates for their own domains but cannot provision certificates for tenant custom domains. We use Cloudflare Origin Certificates for end-to-end encryption.

2. **Dynamic routing without restart**: Customer sites deployed to IPFS/Arweave need proxy routes created automatically. The etcd backend enables hot-reload within ~10 seconds.

### Deployment Modes

| Mode | Image Tag | Use Case |
|------|-----------|----------|
| **Static** | `:main` | Fixed routes in `pingap.toml`, manual updates |
| **Dynamic** | `:etcd` | Routes managed via etcd, auto-updated by service-cloud-api |

### Why Pingap over Caddy?

| Feature | Pingap | Caddy |
|---------|--------|-------|
| Memory usage | ~15MB | ~30MB |
| CPU usage | 70% less | Baseline |
| Hot reload | Native etcd | Requires restart |
| Custom build | No | Yes (xcaddy) |
| Framework | Rust (Pingora) | Go |

## Architecture

### Static Mode (Current)

```
                         Internet
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│              DNS (Cloudflare + Google + deSEC)              │
└───────────────────────────┬─────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                     SSL Proxy (Pingap)                       │
│  • Cloudflare Origin Certificate (Full Strict)              │
│  • Static routes in pingap.toml                              │
└───────────────────────────┬─────────────────────────────────┘
                            │
            ┌───────────────┼───────────────┐
            ▼               ▼               ▼
      ┌──────────┐   ┌──────────┐   ┌──────────┐
      │ Auth API │   │ GraphQL  │   │ Web App  │
      └──────────┘   │   API    │   └──────────┘
                     └──────────┘
```

### Dynamic Mode (etcd)

```
                         Internet
                            │
        Customer Domains    │    Core Services
     docs.example.com       │    auth.alternatefutures.ai
     mysite.xyz             │    api.alternatefutures.ai
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                     SSL Proxy (Pingap)                       │
│  • Cloudflare Origin Certificate                             │
│  • Dynamic routes from etcd (--autoreload)                  │
│  • Hot-reload ~10 seconds                                    │
└───────────────────────────┬─────────────────────────────────┘
                            │
                       ┌────┴────┐
                       │  etcd   │◄────── service-cloud-api
                       └────┬────┘        (writes routes)
                            │
     ┌──────────────────────┼──────────────────────┐
     ▼                      ▼                      ▼
┌──────────┐          ┌──────────┐          ┌──────────┐
│   IPFS   │          │ Arweave  │          │  Akash   │
│ Gateway  │          │ Gateway  │          │ Services │
└──────────┘          └──────────┘          └──────────┘
```

## Files

| File | Purpose |
|------|---------|
| `Dockerfile` | Pingap image with etcdctl for dynamic mode |
| `pingap.toml` | Static proxy configuration (bootstrap) |
| `entrypoint-etcd.sh` | Dynamic mode entrypoint (etcd bootstrap + Pingap) |
| `entrypoint.sh` | Static mode entrypoint |
| `deploy-akash.yaml` | Multi-container Akash SDL (etcd + Pingap) |
| `SSL_ARCHITECTURE.md` | Detailed SSL/TLS documentation |
| `Caddyfile` | (Deprecated) Old Caddy config |

## Dynamic Routing (etcd Mode)

When deployed with the `:etcd` image tag, the proxy uses etcd as a configuration backend. This enables:

- **Automatic route creation** when sites are deployed via service-cloud-api
- **Hot-reload** without container restart (~10 second propagation)
- **Route persistence** across proxy restarts
- **Centralized management** of all proxy routes

### etcd Key Structure

```
/pingap/config/
  ├── basic.toml              # Global Pingap settings
  ├── certificates/
  │   └── alternatefutures.toml  # Cloudflare Origin Cert
  ├── upstreams/
  │   ├── ipfs-gateway.toml   # Shared IPFS gateway
  │   ├── arweave-gateway.toml
  │   ├── auth.toml           # Core service
  │   └── api.toml            # Core service
  ├── locations/
  │   ├── auth.toml           # Core route
  │   ├── api.toml            # Core route
  │   └── {routeId}.toml      # Customer site routes
  └── servers/
      ├── https.toml          # Main HTTPS server
      └── health.toml         # Health check server
```

### Route Types

| Backend Type | Use Case | Upstream |
|--------------|----------|----------|
| `IPFS` | Static sites on IPFS | `gateway.pinata.cloud` with CID rewrite |
| `ARWEAVE` | Permanent sites on Arweave | `arweave.net` with TX rewrite |
| `AKASH` | Dynamic apps on Akash | Direct to provider URL |
| `FUNCTION` | Serverless functions | Function runtime endpoint |
| `EXTERNAL` | External URLs | Custom upstream |

### Integration with service-cloud-api

The `ProxyRoutingService` in service-cloud-api automatically manages routes:

```
Deployment SUCCESS → handleDeploymentSuccess() → etcd route created
Domain VERIFIED   → handleDomainVerified()    → etcd route created
Site DELETED      → removeRoute()              → etcd route removed
```

## Domains Handled

| Domain | Backend |
|--------|---------|
| `auth.alternatefutures.ai` | Auth service |
| `api.alternatefutures.ai` | GraphQL API |
| `app.alternatefutures.ai` | Web dashboard |

## Prerequisites

1. **Cloudflare Account** (free tier)
   - Add `alternatefutures.ai` domain
   - Create API token with `Zone:DNS:Edit` permission
   - Zone must be `active` status

2. **Multi-Provider DNS** (see `infrastructure-dns` repo)
   - Cloudflare, Google Cloud DNS, deSEC
   - ACME challenges delegated to Cloudflare

## Local Development

```bash
# Build the image
docker build -t ssl-proxy .

# Run locally
docker run -p 443:443 -p 8080:8080 \
  -e PINGAP_DNS_SERVICE_URL="https://api.cloudflare.com?token=your-token" \
  ssl-proxy

# Health check
curl http://localhost:8080/health
```

## Deployment

### Via GitHub Actions

1. Push to `main` branch triggers build
2. Image pushed to `ghcr.io/alternatefutures/infrastructure-proxy-pingap`
3. Manual deployment via Akash Console or MCP

### Manual Akash Deployment

```bash
# Using Akash MCP or Console with deploy-akash.yaml
# Set env var:
PINGAP_DNS_SERVICE_URL=https://api.cloudflare.com?token=<CF_API_TOKEN>
```

## Environment Variables

### Static Mode

| Variable | Format | Description |
|----------|--------|-------------|
| `PINGAP_DNS_SERVICE_URL` | `https://api.cloudflare.com?token=xxx` | Cloudflare API for DNS-01 |

### Dynamic Mode (etcd)

| Variable | Example | Description |
|----------|---------|-------------|
| `PINGAP_ETCD_ADDR` | `http://etcd:2379` | etcd cluster address |
| `PINGAP_ETCD_PREFIX` | `/pingap/config` | Key prefix for config |
| `PINGAP_TLS_CERT` | `-----BEGIN CERT...` | Cloudflare Origin Certificate (PEM) |
| `PINGAP_TLS_KEY` | `-----BEGIN KEY...` | Private key (PEM) |
| `PINGAP_ADMIN_ADDR` | `0.0.0.0:3018` | Admin interface address |
| `ETCD_ROOT_PASSWORD` | (optional) | etcd authentication password |

## Monitoring

### Health Check

```bash
curl http://<provider>:<health-port>/health
# Current: http://provider.sa1.pl:32077/health
```

### Certificate Status

```bash
echo | openssl s_client -connect auth.alternatefutures.ai:443 2>/dev/null | \
  openssl x509 -noout -dates -issuer
```

### Logs

Via Akash MCP:
```
get-logs with dseq=24576255, provider=akash162gym3szcy9d993gs3tyu0mg2ewcjacen9nwsu
```

## Troubleshooting

### Certificate not provisioning

1. Check Cloudflare zone status is `active` (not `initializing`)
2. Verify `PINGAP_DNS_SERVICE_URL` format is correct
3. Check logs for ACME errors: `lookup dns txt record of _acme-challenge...`

### 502 Bad Gateway

1. Verify backend services are running
2. Check backend addresses in `pingap.toml`
3. Ensure Akash internal networking allows service-to-service communication

### Image caching on provider

If provider serves old image:
- Change image name (append `-v2`, etc.)
- Or use SHA tag instead of `:main`

## Related Repositories

- [`infrastructure-dns`](../infrastructure-dns) - Multi-provider DNS management
- [`service-auth`](../service-auth) - Authentication service
- [`service-cloud-api`](../service-cloud-api) - GraphQL API
