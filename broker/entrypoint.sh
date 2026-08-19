#!/usr/bin/env bash
# Redpanda broker — dual named Kafka listeners (validated idiom).
#
#   INTERNAL:  bind 0.0.0.0:9092   advertise ${RAILWAY_PRIVATE_DOMAIN}:9092
#              -> same-project services (Console) + private-network clients.
#   EXTERNAL:  bind 0.0.0.0:9093   advertise ${RAILWAY_TCP_PROXY_DOMAIN}:${RAILWAY_TCP_PROXY_PORT}
#              -> external Kafka clients reach it via Railway's L4 (raw TCP) proxy.
#
# The EXTERNAL listener MUST advertise the public proxy endpoint (not a private
# IP) or external clients dial an address they can't route to. When the TCP
# proxy is not enabled (var empty), EXTERNAL falls back to the private domain
# so it still advertises a routable address rather than an empty string.
#
# --smp/--overprovisioned keep a single-node deploy valid on small Railway
# instances (1 vCPU / 512MB). Schema Registry auto-binds 0.0.0.0:8081.
set -e

DATA_DIR="${DATA_DIR:-/var/lib/redpanda/data}"
INTERNAL_HOST="${INTERNAL_HOST:-${RAILWAY_PRIVATE_DOMAIN:-localhost}}"
INTERNAL_PORT="${INTERNAL_PORT:-9092}"
EXTERNAL_BIND_PORT="${EXTERNAL_BIND_PORT:-9093}"
EXTERNAL_HOST="${EXTERNAL_HOST:-${RAILWAY_TCP_PROXY_DOMAIN:-$INTERNAL_HOST}}"
EXTERNAL_PORT="${EXTERNAL_PORT:-${RAILWAY_TCP_PROXY_PORT:-$EXTERNAL_BIND_PORT}}"
RPC_HOST="${RPC_HOST:-127.0.0.1}"
RPC_PORT="${RPC_PORT:-33145}"

mkdir -p "$DATA_DIR"
# Make the data tree writable by the redpanda user on a fresh (root-owned) volume.
if getent group redpanda >/dev/null 2>&1; then
  chown -R redpanda:redpanda "$DATA_DIR" 2>/dev/null || true
fi

echo "[redpanda] INTERNAL bind=0.0.0.0:${INTERNAL_PORT} advertise=${INTERNAL_HOST}:${INTERNAL_PORT}"
echo "[redpanda] EXTERNAL bind=0.0.0.0:${EXTERNAL_BIND_PORT} advertise=${EXTERNAL_HOST}:${EXTERNAL_PORT}"
echo "[redpanda] DATA_DIR=${DATA_DIR}"

exec /usr/bin/rpk \
  --kafka-addr           "INTERNAL://0.0.0.0:${INTERNAL_PORT},EXTERNAL://0.0.0.0:${EXTERNAL_BIND_PORT}" \
  --advertise-kafka-addr "INTERNAL://${INTERNAL_HOST}:${INTERNAL_PORT},EXTERNAL://${EXTERNAL_HOST}:${EXTERNAL_PORT}" \
  --rpc-addr             "${RPC_HOST}:${RPC_PORT}" \
  --advertise-rpc-addr   "${INTERNAL_HOST}:${RPC_PORT}" \
  redpanda start \
    --node-id     "${NODE_ID:-0}" \
    --smp         "${SMP:-1}" \
    --overprovisioned \
    --well-known-io unknown:unknown:unknown
