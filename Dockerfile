# Upstream: redpandadata/console (Redpanda Console — Kafka web UI)
# Pinned stable release (no :latest per repo gate). v3.10.0
FROM redpandadata/console:v3.10.0

COPY entrypoint.sh /usr/local/bin/console-entrypoint.sh

# Console listens here; Railway routes the public domain to $PORT.
ENV WEB_PORT=8080
EXPOSE 8080

# Console image serves /health on $WEB_PORT. Use 127.0.0.1 (not localhost):
# `localhost` can resolve ::1-first on Railway's gVisor runtime and fail the
# probe even while the server is up.
HEALTHCHECK --interval=30s --timeout=10s --start-period=90s --retries=5 \
  CMD wget --no-verbose --tries=1 --spider http://127.0.0.1:8080/health || exit 1

# Invoke via sh so no exec bit / chmod is needed (portable across buildkit/buildah).
ENTRYPOINT ["sh", "/usr/local/bin/console-entrypoint.sh"]
