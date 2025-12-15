# Pingap SSL Proxy with etcd Support
#
# Dynamic configuration via etcd backend for hot-reload.
# Routes update within 10 seconds without restart.
#
# High-performance reverse proxy built on Cloudflare's Pingora.
# Uses Cloudflare Origin Certificate (avoids ACME DNS propagation issues).

FROM vicanso/pingap:latest

# Install etcdctl for initialization and debugging
# Also install curl for health checks
RUN apk add --no-cache curl && \
    ETCD_VER=v3.5.12 && \
    ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/') && \
    curl -L https://github.com/etcd-io/etcd/releases/download/${ETCD_VER}/etcd-${ETCD_VER}-linux-${ARCH}.tar.gz -o /tmp/etcd.tar.gz && \
    tar xzf /tmp/etcd.tar.gz -C /tmp && \
    mv /tmp/etcd-${ETCD_VER}-linux-${ARCH}/etcdctl /usr/local/bin/ && \
    rm -rf /tmp/etcd*

# Copy configuration files
COPY pingap.toml /etc/pingap/pingap-bootstrap.toml
COPY entrypoint-etcd.sh /entrypoint.sh
# Keep old entrypoint for backwards compatibility
COPY entrypoint.sh /entrypoint-static.sh

# Make scripts executable and create directories
RUN chmod +x /entrypoint.sh /entrypoint-static.sh && \
    mkdir -p /etc/pingap/certs /data/pingap /var/log/pingap

# Expose ports
# 443  - HTTPS traffic
# 8080 - Health check
# 3018 - Admin UI
EXPOSE 443 8080 3018

# Health check - check internal health endpoint
HEALTHCHECK --interval=30s --timeout=3s --start-period=60s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:8080/health || exit 1

# Use etcd-aware entrypoint
ENTRYPOINT ["/entrypoint.sh"]
