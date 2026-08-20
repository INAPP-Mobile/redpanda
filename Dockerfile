# Upstream: redpandadata/console (Redpanda Console — Kafka web UI)
# Pinned stable release (no :latest per repo gate). v3.10.0
FROM redpandadata/console:v3.10.0

# Console listens here; Railway routes the public domain to $PORT.
ENV PORT=8080
ENV WEB_PORT=8080
EXPOSE 8080

COPY entrypoint.sh /usr/local/bin/console-entrypoint.sh

# Console image serves /health on $WEB_PORT. Use 127.0.0.1 (not localhost):
# `localhost` can resolve ::1-first on Railway's gVisor runtime and fail the
# probe even while the server is up.
HEALTHCHECK --interval=30s --timeout=15s --start-period=300s --retries=10 \
  CMD curl -fsS -o /dev/null http://127.0.0.1:8080/health || exit 1

ENTRYPOINT ["sh", "/usr/local/bin/console-entrypoint.sh"]
