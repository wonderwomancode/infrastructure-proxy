# AlternateFutures SSL Proxy

Caddy-based SSL termination proxy for AlternateFutures services running on Akash Network.

## Overview

This proxy solves a key challenge with Akash Network: providers use DNS-01 Let's Encrypt challenges with wildcard certificates for their own domains, but **cannot** provision certificates for tenant custom domains.

Our solution uses Caddy with the Cloudflare DNS plugin to obtain Let's Encrypt certificates via DNS-01 challenges, enabling automatic SSL for custom domains on Akash.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      Internet                                │
└───────────────────────────┬─────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│              DNS (Cloudflare + Google + deSEC)              │
│                   Multi-provider redundancy                  │
└───────────────────────────┬─────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                    Akash Provider Ingress                    │
└───────────────────────────┬─────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                      SSL Proxy (Caddy)                       │
│                                                              │
│  • DNS-01 Let's Encrypt via Cloudflare API                  │
│  • Automatic cert provisioning & renewal                     │
│  • HSTS, security headers                                    │
│  • Routes to backend services                                │
└───────────────────────────┬─────────────────────────────────┘
                            │
            ┌───────────────┼───────────────┐
            ▼               ▼               ▼
      ┌──────────┐   ┌──────────┐   ┌──────────┐
      │ Auth API │   │ GraphQL  │   │ Web App  │
      │  :3000   │   │   API    │   │  :3000   │
      └──────────┘   │  :4000   │   └──────────┘
                     └──────────┘
```

## Files

| File | Purpose |
|------|---------|
| `Dockerfile` | Custom Caddy build with Cloudflare DNS plugin |
| `Caddyfile` | Proxy configuration with DNS-01 TLS |
| `deploy-akash.yaml` | Akash SDL for deployment |
| `SSL_ARCHITECTURE.md` | Detailed SSL/TLS documentation |

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

2. **Multi-Provider DNS** (see `infrastructure-dns` repo)
   - Cloudflare, Google Cloud DNS, deSEC
   - ACME challenges delegated to Cloudflare

## Local Development

```bash
# Build the image
docker build -t ssl-proxy .

# Run locally (requires CF_API_TOKEN)
docker run -p 80:80 -p 443:443 -p 8080:8080 \
  -e CF_API_TOKEN=your-token \
  -e AUTH_BACKEND=localhost:3001 \
  ssl-proxy

# Health check
curl http://localhost:8080/health
```

## Deployment

### Via GitHub Actions

1. Push to `main` branch triggers build
2. Image pushed to `ghcr.io/alternatefutures/ssl-proxy`
3. Manual deployment via Akash Console or CLI

### Manual Akash Deployment

```bash
# Using Akash CLI
akash tx deployment create deploy-akash.yaml \
  --from deployer \
  --deposit 500000uakt

# Set the CF_API_TOKEN in the deployment
```

### Required Secrets

| Secret | Description | Where |
|--------|-------------|-------|
| `CF_API_TOKEN` | Cloudflare API token | Akash deployment |
| `GHCR_PAT` | GitHub Container Registry | Akash deployment |

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `CF_API_TOKEN` | (required) | Cloudflare API token for DNS-01 |
| `AUTH_BACKEND` | `auth-api:3000` | Auth service address |
| `API_BACKEND` | `api-service:4000` | GraphQL API address |
| `APP_BACKEND` | `web-app:3000` | Web app address |

## Monitoring

### Health Check

```bash
curl https://proxy.alternatefutures.ai:8080/health
# Returns: OK
```

### Certificate Status

```bash
echo | openssl s_client -connect auth.alternatefutures.ai:443 2>/dev/null | \
  openssl x509 -noout -dates -issuer
```

### Logs

Via Akash provider:
```bash
provider-services lease-logs \
  --dseq $DSEQ \
  --provider $PROVIDER
```

## Troubleshooting

### Certificate not provisioning

1. Check `CF_API_TOKEN` has `Zone:DNS:Edit` permission
2. Verify DNS delegation: `dig _acme-challenge.auth.alternatefutures.ai NS`
3. Check Caddy logs for ACME errors

### 502 Bad Gateway

1. Verify backend services are running
2. Check backend addresses in environment variables
3. Ensure Akash internal networking allows service-to-service communication

## Related Repositories

- [`infrastructure-dns`](../infrastructure-dns) - Multi-provider DNS management
- [`service-auth`](../service-auth) - Authentication service
- [`service-cloud-api`](../service-cloud-api) - GraphQL API
- [`.github`](https://github.com/alternatefutures/.github) - Organization docs & DEPLOYMENTS.md
