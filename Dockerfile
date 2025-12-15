# Pingap SSL Proxy for AlternateFutures
#
# High-performance reverse proxy built on Cloudflare's Pingora.
# Uses Cloudflare Origin Certificate (avoids ACME DNS propagation issues).

FROM vicanso/pingap:latest

# Copy configuration and entrypoint
COPY pingap.toml /etc/pingap/pingap.toml
COPY entrypoint.sh /entrypoint.sh

# Make scripts executable and create directories
RUN chmod +x /entrypoint.sh && \
    mkdir -p /etc/pingap/certs /data/pingap /var/log/pingap

# Expose ports
# 443  - HTTPS traffic
# 8080 - Health check
EXPOSE 443 8080

# Use static config entrypoint
ENTRYPOINT ["/entrypoint.sh"]
