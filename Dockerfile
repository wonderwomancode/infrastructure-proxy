# Custom Caddy build with Cloudflare DNS module for DNS-01 challenges
#
# This enables automatic Let's Encrypt certificate provisioning
# via DNS-01 challenges using the Cloudflare API.

FROM caddy:2-builder AS builder

# Build Caddy with Cloudflare DNS plugin
RUN xcaddy build \
    --with github.com/caddy-dns/cloudflare

FROM caddy:2-alpine

# Copy custom-built Caddy with DNS plugin
COPY --from=builder /usr/bin/caddy /usr/bin/caddy

# Copy Caddyfile
COPY Caddyfile /etc/caddy/Caddyfile

# Create data directories for certificates
RUN mkdir -p /data/caddy /config/caddy

# Expose ports
# Note: On Akash, these go through provider ingress
EXPOSE 80 443 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=30s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:8080/health || exit 1

# Run Caddy
CMD ["caddy", "run", "--config", "/etc/caddy/Caddyfile", "--adapter", "caddyfile"]
