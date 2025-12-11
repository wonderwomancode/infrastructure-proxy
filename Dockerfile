# Pingap SSL Proxy - Built on Cloudflare's Pingora
#
# High-performance reverse proxy with native DNS-01 Let's Encrypt
# via Cloudflare API. Uses ~70% less resources than nginx/caddy.

FROM vicanso/pingap:latest

# Copy configuration
COPY pingap.toml /etc/pingap/pingap.toml

# Create data directories for certificates
RUN mkdir -p /data/pingap /var/log/pingap

# Expose ports
EXPOSE 443 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=30s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:8080/health || exit 1

# Run Pingap
CMD ["pingap", "-c", "/etc/pingap/pingap.toml"]

