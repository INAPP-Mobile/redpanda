# Upstream: redpandadata/redpanda (Redpanda data platform — Kafka API)
# Pinned stable release (no :latest per repo gate). v26.1.16
FROM redpandadata/redpanda:v26.1.16

# Run as root so we can chown a fresh, root-owned volume before the broker
# process (uid redpanda) needs it. (Matches repo "prefer root+chown" volume pattern.)
USER root
# This service's root directory is broker/ (see plausible/clickhouse rootDirectory
# convention), so the build context is this directory — COPY uses sibling-relative paths.
COPY entrypoint.sh /usr/local/bin/broker-entrypoint.sh

# PORT=9644 -> Railway healthcheck + any HTTP domain target the Admin API
# (the /v1/status/ready we healthcheck). Kafka binary protocol lives on 9092/9093.
ENV PORT=9644
ENV DATA_DIR=/var/lib/redpanda/data
EXPOSE 9644 9092 9093 8081

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=5 \
  CMD curl -fsS http://localhost:9644/v1/status/ready || exit 1

# Invoke via bash (entrypoint uses `exec`; broker image ships bash). No exec bit / chmod needed.
ENTRYPOINT ["bash", "/usr/local/bin/broker-entrypoint.sh"]
