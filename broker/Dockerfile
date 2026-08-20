# Upstream: redpandadata/redpanda (Redpanda data platform — Kafka API)
# Pinned stable release (no :latest per repo gate). v26.1.16
FROM redpandadata/redpanda:v26.1.16

# Cache buster — invalidate RAILPACK layer cache when the shim changes.
# Increment to force a fresh COPY of healthd.pl.
ARG CACHE_BUSTER=4
RUN echo "cache buster: $CACHE_BUSTER"

# Run as root so we can chown a fresh, root-owned volume before the broker
# process (uid redpanda) needs it. (Matches repo "prefer root+chown" volume pattern.)
USER root
# This service's root directory is broker/ (see plausible/clickhouse rootDirectory
# convention), so the build context is this directory — COPY uses sibling-relative paths.
COPY entrypoint.sh /usr/local/bin/broker-entrypoint.sh
COPY healthd.pl /usr/local/bin/healthd.pl

# Primary port = 8080, served by healthd.pl (below). Railway's RAILPACK build
# probe hits the primary port with a fixed path (/health). Redpanda's Admin API
# has no /health route, so the shim answers /health on 8080 and reflects redpanda's
# /v1/status/ready (200 once the broker is ready). The Admin API stays on 9644.
# Kafka binary protocol lives on 9092 (internal) / 9093 (external).
ENV PORT=8080
ENV HEALTH_PORT=8080
ENV ADMIN_PORT=9644
ENV DATA_DIR=/var/lib/redpanda/data
EXPOSE 8080 9644 9092 9093 8081

# Healthcheck probes the PRIMARY port (8080) — the health shim — which answers
# /health with 200 once redpanda is ready (else 503). 127.0.0.1 (not localhost)
# so gVisor's ::1-first resolution can't break it. Generous start-period: redpanda
# boots ~60-120s (longer under gVisor).
HEALTHCHECK --interval=30s --timeout=15s --start-period=300s --retries=10 \
  CMD curl -fsS -o /dev/null http://127.0.0.1:8080/health || exit 1

# Invoke via bash (entrypoint uses `exec`; broker image ships bash). No exec bit / chmod needed.
ENTRYPOINT ["bash", "/usr/local/bin/broker-entrypoint.sh"]
