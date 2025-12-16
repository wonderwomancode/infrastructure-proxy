# Akash IP Lease for Custom Domain Routing

## The Problem

Akash's default HTTP ingress uses a shared nginx that routes based on **auto-generated hostnames only** (e.g., `*.ingress.europlots.com`). Custom domains in the SDL `accept` list are NOT routed by the provider nginx.

```
Without IP Lease:
User → secrets.alternatefutures.ai
     → Cloudflare proxy
     → Provider nginx (sees Host: secrets.alternatefutures.ai)
     → 404 (nginx doesn't recognize this hostname)
     → Container never receives traffic
```

The `accept` list is only for validation/documentation - it does NOT configure nginx routing.

## The Solution: IP Lease

Akash [IP Leases](https://docs.akash.network/features/ip-leases) provide a dedicated public IPv4 address that bypasses the provider's shared nginx entirely.

```
With IP Lease:
User → secrets.alternatefutures.ai
     → Cloudflare proxy
     → Dedicated IP:443 (directly to container)
     → Pingap receives request with original Host header
     → Routes to correct backend
```

## SDL Configuration

Add an `endpoints` section at the top level:

```yaml
version: "2.0"

# Declare IP endpoint
endpoints:
  proxy-ip:
    kind: ip

services:
  ssl-proxy:
    image: ghcr.io/wonderwomancode/infrastructure-proxy-pingap:main
    expose:
      - port: 443
        as: 443
        to:
          - global: true
            ip: proxy-ip  # Bind to leased IP
```

Key points:
- `endpoints.proxy-ip.kind: ip` declares an IP lease requirement
- `ip: proxy-ip` in the expose section binds that port to the leased IP
- Only providers with available IP addresses will bid
- The IP is retained across manifest updates (same deployment)

## Deployment Steps

1. **Deploy with IP Lease SDL**
   ```bash
   # Use deploy-akash-ip-lease.yaml (NOT deploy-akash.yaml)
   ```

2. **Get Leased IP**
   After deployment, the leased IP appears in:
   - Akash Console: Deployment → Leases → IP Address
   - CLI: `akash query market lease-status`

3. **Update DNS**
   Create A records pointing to the leased IP:
   ```
   secrets.alternatefutures.ai  A  <LEASED_IP>
   auth.alternatefutures.ai     A  <LEASED_IP>
   api.alternatefutures.ai      A  <LEASED_IP>
   ```

4. **Configure TLS**
   Set environment variables for Origin Certificate:
   ```
   PINGAP_TLS_CERT=<cert with newlines as pipes>
   PINGAP_TLS_KEY=<key with newlines as pipes>
   ```

## IP Lease Limitations

- **Provider support**: Not all providers offer IP leases
- **Cost**: IP addresses may cost extra (provider-dependent)
- **One IP per deployment**: Each deployment gets max one IPv4
- **Retained on update**: IP stays the same when updating manifest
- **Released on close**: IP returns to pool when deployment closes

## Files

| File | Purpose |
|------|---------|
| `deploy-akash-ip-lease.yaml` | SDL with IP lease (USE THIS) |
| `deploy-akash.yaml` | SDL without IP lease (legacy, custom domains broken) |

## Troubleshooting

### No bids received
- Provider may not have IP addresses available
- Try different providers or wait

### Custom domain still 404
- Verify DNS A record points to leased IP (not CNAME)
- Check Cloudflare is in proxy mode (orange cloud)
- Verify Pingap has correct routes in pingap.toml

### TLS errors
- Ensure Origin Certificate covers all domains
- Check cert/key are correctly escaped in env vars

## Host Header Rewriting

**CRITICAL**: When proxying to Akash backends, you must rewrite the Host header.

Akash provider nginx routes based on Host header. If you forward your custom domain Host to the backend, their nginx returns 404 because it doesn't recognize it.

**Correct pingap.toml configuration:**
```toml
[locations.secrets]
upstream = "secrets"
host = "secrets.alternatefutures.ai"  # Match incoming requests
path = "/"
proxy_set_headers = [
  "Host: v8c1fui9p1dah5m86ctithi5ok.ingress.europlots.com",  # Backend's expected Host
  "X-Forwarded-Proto: https",
  "X-Forwarded-Host: secrets.alternatefutures.ai",  # Original for app awareness
  "X-Real-IP: $remote_addr"
]
```

**Without Host rewrite:**
```
User → secrets.alternatefutures.ai → Pingap → Backend nginx
                                              ↳ 404 (nginx doesn't recognize Host)
```

**With Host rewrite:**
```
User → secrets.alternatefutures.ai → Pingap (rewrites Host) → Backend nginx
                                                              ↳ 200 (nginx routes correctly)
```

## Current Deployment

| Field | Value |
|-------|-------|
| DSEQ | 24648398 |
| Provider | akash1aaul837r7en7hpk9wv2svg8u78fdq0t2j2e82z |
| Dedicated IP | **77.76.13.214** |
| Image | ghcr.io/wonderwomancode/infrastructure-proxy-pingap:7235adc |
| Port 443 | Direct to container |
| Port 80 | Direct to container |

## DNS Configuration

Update Cloudflare A records to point to dedicated IP:

```
secrets.alternatefutures.ai  A  77.76.13.214  (proxied)
auth.alternatefutures.ai     A  77.76.13.214  (proxied)
api.alternatefutures.ai      A  77.76.13.214  (proxied)
app.alternatefutures.ai      A  77.76.13.214  (proxied)
docs.alternatefutures.ai     A  77.76.13.214  (proxied)
```

## References

- [Akash IP Leases Documentation](https://docs.akash.network/features/ip-leases)
- [IP Leases SDL Example](https://docs.akash.network/features/ip-leases/full-sdl-example-with-ip-leases)
- [IP Operator Setup](https://akash.network/docs/akash-provider-operators/akash-operator-overview/ip-operator-for-ip-leases/)
