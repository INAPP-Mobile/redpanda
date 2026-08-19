#!/bin/sh
# Redpanda Console startup (primary service).
#
# The upstream image natively binds KAFKA_BROKERS / WEB_PORT / SCHEMA_REGISTRY_URL
# from the environment (verified against the binary — no config file required).
# The ONLY job of this entrypoint is startup ordering: Console exits(1) if the
# sibling broker is not yet accepting TCP connections, so we block on a bounded
# nc wait first (bounded at ~120s, then hand to Console's own retry loop).
set -e

KB="${KAFKA_BROKERS:-broker.railway.internal:9092}"
HOST="${KB%%:*}"
PORT="${KB##*:}"

echo "[console] booting Console on :${WEB_PORT:-8080} (kafka=${KB})"
i=0
until nc -z "$HOST" "$PORT" 2>/dev/null; do
  i=$((i + 1))
  if [ "$i" -ge 60 ]; then
    echo "[console] broker ${HOST}:${PORT} not reachable after 120s; starting Console anyway (it self-retries)."
    break
  fi
  echo "[console] waiting for broker ${HOST}:${PORT} ... ($i)"
  sleep 2
done

exec /app/console
