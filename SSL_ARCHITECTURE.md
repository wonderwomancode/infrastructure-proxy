# SSL/TLS Architecture

How AlternateFutures handles SSL certificates for custom domains on decentralized infrastructure.

## The Challenge

Akash Network providers use **DNS-01 Let's Encrypt challenges** with wildcard certificates for their own domains (e.g., `*.europlots.com`). They **cannot** provision certificates for tenant custom domains because:

1. DNS-01 requires control over the domain's DNS records
2. Providers don't have API access to tenant DNS
3. HTTP-01 challenges are intercepted by the provider's ingress

## Our Solution

We use a **hybrid approach**:

1. **Compute**: Akash Network (decentralized)
2. **SSL Termination**: Caddy proxy on Akash with DNS-01 via Cloudflare API
3. **DNS**: Multi-provider (Cloudflare + Google + deSEC) for redundancy

```
┌─────────────────────────────────────────────────────────────────┐
│                         User Request                            │
│                  https://auth.alternatefutures.ai               │
└───────────────────────────┬─────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│                    DNS Resolution                                │
│         (Cloudflare OR Google OR deSEC - any responds)          │
│                            │                                     │
│                            ▼                                     │
│              CNAME → Akash Provider Ingress IP                   │
└───────────────────────────┬─────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│                 Akash Provider Ingress                           │
│              (Europlots / other provider)                        │
│                            │                                     │
│    Routes based on Host header to correct deployment             │
└───────────────────────────┬─────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Caddy SSL Proxy                               │
│                   (Running on Akash)                             │
│                            │                                     │
│  1. Terminates TLS with Let's Encrypt cert                      │
│  2. Cert obtained via DNS-01 challenge (Cloudflare API)         │
│  3. Proxies to backend service                                   │
└───────────────────────────┬─────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Backend Service                               │
│              (Auth API, GraphQL API, etc.)                       │
│                  Also running on Akash                           │
└─────────────────────────────────────────────────────────────────┘
```

## Certificate Provisioning Flow

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Caddy     │     │ Let's       │     │ Cloudflare  │
│   Proxy     │     │ Encrypt     │     │    DNS      │
└──────┬──────┘     └──────┬──────┘     └──────┬──────┘
       │                   │                   │
       │  1. Request cert  │                   │
       │  for auth.alt...  │                   │
       │──────────────────>│                   │
       │                   │                   │
       │  2. Create TXT    │                   │
       │  record challenge │                   │
       │<──────────────────│                   │
       │                   │                   │
       │  3. Create        │                   │
       │  _acme-challenge  │                   │
       │  TXT record       │                   │
       │───────────────────────────────────────>
       │                   │                   │
       │  4. Record        │                   │
       │  created OK       │                   │
       │<───────────────────────────────────────
       │                   │                   │
       │  5. Challenge     │                   │
       │  ready            │                   │
       │──────────────────>│                   │
       │                   │                   │
       │                   │  6. Query DNS     │
       │                   │  for TXT record   │
       │                   │──────────────────>│
       │                   │                   │
       │                   │  7. TXT record    │
       │                   │  verified         │
       │                   │<──────────────────│
       │                   │                   │
       │  8. Certificate   │                   │
       │  issued!          │                   │
       │<──────────────────│                   │
       │                   │                   │
       │  9. Delete TXT    │                   │
       │  record           │                   │
       │───────────────────────────────────────>
       │                   │                   │
```

## Why DNS-01 Instead of HTTP-01?

| Aspect | HTTP-01 | DNS-01 |
|--------|---------|--------|
| Port 80 required | Yes | No |
| Works on Akash | No (ingress intercepts) | Yes |
| Wildcard certs | No | Yes |
| DNS API needed | No | Yes |
| Speed | Faster | Slower (DNS propagation) |

We chose DNS-01 because Akash provider ingress intercepts HTTP traffic before it reaches our containers, making HTTP-01 impossible.

## Redundancy & Failure Modes

### DNS Redundancy

ACME challenges use Cloudflare, but main DNS is multi-provider:

| Component | Primary | Fallback |
|-----------|---------|----------|
| Main DNS | Any of 3 providers | Others continue serving |
| ACME challenges | Cloudflare only | None (certs valid 90 days) |
| SSL termination | Caddy on Akash | - |

### Failure Scenarios

| Failure | Impact | Duration | Mitigation |
|---------|--------|----------|------------|
| Cloudflare DNS down | New certs fail | Until recovery | Existing certs valid 90 days |
| Google DNS down | None (others serve) | - | Multi-provider redundancy |
| deSEC down | None (others serve) | - | Multi-provider redundancy |
| Akash provider down | Site down | Until migration | Redeploy to different provider |
| Caddy container crash | Site down | Seconds | Akash auto-restarts containers |

## Configuration Files

### Caddy (DNS-01 with Cloudflare)

```
# service-auth/caddy-proxy/Caddyfile
{
    email admin@alternatefutures.ai
}

auth.alternatefutures.ai {
    tls {
        dns cloudflare {env.CF_API_TOKEN}
    }
    reverse_proxy auth-api:3000
}
```

### Environment Variables

| Variable | Description | Where |
|----------|-------------|-------|
| `CF_API_TOKEN` | Cloudflare API token (DNS edit) | Akash deployment secret |
| `CLOUDFLARE_API_TOKEN` | Same, for OctoDNS | GitHub Actions secret |
| `GOOGLE_DNS_CREDENTIALS` | Google Cloud service account | GitHub Actions secret |
| `DESEC_API_TOKEN` | deSEC API token | GitHub Actions secret |

## Setup Checklist

- [ ] Add domain to Cloudflare (free tier)
- [ ] Create Cloudflare API token with `Zone:DNS:Edit`
- [ ] Set up Google Cloud DNS zone
- [ ] Create Google service account with DNS Admin role
- [ ] Register at deSEC.io and add domain
- [ ] Update domain registrar NS records to all 3 providers
- [ ] Add secrets to GitHub repository
- [ ] Deploy Caddy proxy to Akash with CF_API_TOKEN
- [ ] Test certificate issuance

## Monitoring

### Certificate Expiry

Caddy auto-renews certificates 30 days before expiry. Monitor with:

```bash
# Check cert expiry
echo | openssl s_client -connect auth.alternatefutures.ai:443 2>/dev/null | openssl x509 -noout -dates
```

### DNS Health

```bash
# Check all providers respond
dig @ns1.cloudflare.com auth.alternatefutures.ai
dig @ns-cloud-a1.googledomains.com auth.alternatefutures.ai
dig @ns1.desec.io auth.alternatefutures.ai
```

## Related Resources

- [infrastructure-dns/](../infrastructure-dns/) - DNS configuration and OctoDNS setup
- [service-auth/caddy-proxy/](../service-auth/caddy-proxy/) - Caddy proxy configuration
- [DEPLOYMENTS.md](./DEPLOYMENTS.md) - Akash deployment details
- [Let's Encrypt Documentation](https://letsencrypt.org/docs/)
- [Caddy DNS Challenge](https://caddyserver.com/docs/automatic-https#dns-challenge)
