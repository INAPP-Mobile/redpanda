<div align="center">
  <img src="template-icon.svg" width="200" alt="Redpanda logo"/>
  <h1 align="center">Redpanda + Console</h1>
  <p align="center"><strong>High-performance Kafka API streaming platform with web console, on Railway</strong></p>
  <p align="center">
    <a href="https://railway.com/deploy/REPLACE_WITH_TEMPLATE_CODE"><img src="https://railway.app/button.svg" alt="Deploy on Railway" height="40"/></a>
  </p>
  <br/>
</div>

# Deploy & Host

**Redpanda** (Kafka-compatible streaming data platform) with **Redpanda Console** (web UI) on Railway. Single click spins up both services with internal networking already wired — no broker env-var hunting, no manual listener configuration.

## Features

- **Kafka wire-compatible** — drop-in replacement for Apache Kafka with the Kafka protocol.
- **Dual named listeners** — an `INTERNAL` listener over the Railway private network (for Console + same-project services) and an `EXTERNAL` listener exposed to the internet through **Railway's L4 (raw TCP) proxy**.
- **Persistent storage** — a Railway volume is attached to the broker so topics and metadata survive restarts and redeploys.
- **Built-in Schema Registry** on `:8081`, enabling per-topic schema views in the console.
- **Auto-topic creation** enabled by default — produce to any topic name immediately.
- **Web console** health endpoint (`/health`) gated on the broker being reachable.

## Quick Start

1. **Deploy** using the button above. Railway creates the `console` and `broker` services in one project and wires the internal network.
   - The broker needs ~30–60s to start a KRaft single node.
   - The console blocks (bounded) until the broker accepts TCP, then serves its UI.
2. **Open the console.** The console service gets a public `*.up.railway.app` domain. Open it and you'll see an empty cluster — no topics yet (auto-create is on).
3. **Produce / consume.** Connect any Kafka client using the bootstrap server shown in the console (the external TCP-proxy endpoint), or the private `broker.railway.internal:9092` from same-project services.

```bash
# Example: any Kafka client against the EXTERNAL (public) listener
kafka-console-producer --bootstrap-server <RAILWAY_TCP_PROXY_DOMAIN>:<RAILWAY_TCP_PROXY_PORT> \
  --topic my-topic
kafka-console-consumer --bootstrap-server <RAILWAY_TCP_PROXY_DOMAIN>:<RAILWAY_TCP_PROXY_PORT> \
  --topic my-topic --from-beginning
```

## Environment

### Console (root service)

| Variable | Default | Notes |
|----------|---------|-------|
| `KAFKA_BROKERS` | `broker.railway.internal:9092` | Bootstrap servers. Points at the sibling `broker` service (INTERNAL listener) over the private network. |
| `SCHEMA_REGISTRY_URL` | `http://broker.railway.internal:8081` | Enables per-topic schema views. Leave empty to disable. |
| `WEB_PORT` | `8080` | Port the console listens on. Railway routes the public domain here. |

### Broker (`broker/` service)

| Variable | Default | Notes |
|----------|---------|-------|
| `DATA_DIR` | `/var/lib/redpanda/data` | Redpanda data directory (topics + metadata). Persistent on the attached volume. |
| `INTERNAL_PORT` | `9092` | Private-network Kafka listener port (Console + same-project services). |
| `SCHEMA_REGISTRY_PORT` | `8081` | Built-in Schema Registry port. |
| `RAILWAY_TCP_PROXY_DOMAIN` / `RAILWAY_TCP_PROXY_PORT` | (injected) | Railway L4 proxy endpoint the `EXTERNAL` listener advertises to external clients. Injected by Railway when the TCP proxy is enabled. |

`DATA_DIR`, `INTERNAL_PORT`, `SCHEMA_REGISTRY_PORT` are the only broker variables you typically need to touch. The listener/advertise addresses are resolved from the runtime environment (private domain + TCP-proxy vars) by `broker/entrypoint.sh`.

## Prerequisites

- A Railway account with a workspace (this deploy targets the `INAPP` workspace).
- Nothing to pre-install — both `redpandadata/redpanda` and `redpandadata/console` are pulled directly from Docker Hub.
- For external Kafka clients: a Kafka client library (librdkafka, kafka-clients, confluent-kafka, etc.). No broker-side client installs are required.

## Architecture

Two services in one Railway project, talking over the project's private network:

```
                     Railway private network
 ┌──────────────────────────────────────────────────────────────┐
 │                                                              │
 │   CONSOLE (public *.up.railway.app :8080)                    │
 │   ┌──────────────────────────────┐                            │
 │   │  redpandadata/console :8080  │── /health ────────────────▶│
 │   └──────────────┬───────────────┘                            │
 │                  │ KAFKA_BROKERS                               │
 │                  │ broker.railway.internal:9092 (INTERNAL)     │
 │                  ▼                                             │
 │   BROKER  ┌──────────────────────────────────────┐            │
 │   (volume)│  redpandadata/redpanda :9644 (admin)  │            │
 │           │  INTERNAL  :9092 ── private network   │            │
 │           │  EXTERNAL  :9093 ── TCP-proxy (L4) ──▶│ internet   │
 │           │  SchemaReg :8081                       │            │
 │           │  /var/lib/redpanda  → Railway volume   │            │
 │           └──────────────────────────────────────┘            │
 └──────────────────────────────────────────────────────────────┘
```

- **INTERNAL listener** (`9092`) advertises `broker.railway.internal:9092` so in-project services and the console reach the broker without any public exposure.
- **EXTERNAL listener** (`9093`) advertises the Railway L4 TCP-proxy endpoint so external Kafka clients can connect over the public internet.
- The volume is mounted at `/var/lib/redpanda` (parent of `DATA_DIR=/var/lib/redpanda/data`) so the volume's `lost+found/` stays outside the data tree and the broker process (uid `redpanda`) can write.

## Deploy

| Aspect | Detail |
|--------|--------|
| Image (console) | `redpandadata/console:v3.10.0` |
| Image (broker) | `redpandadata/redpanda:v26.1.16` |
| Broker volume | `/var/lib/redpanda` (name: `redpanda-data`) |
| Console health path | `/health` |
| Broker health path | `/v1/status/ready` (Admin API, `:9644`) |
| Service naming | Console = root directory, Broker = `broker/` (private DNS `broker.railway.internal`) |

> **TCP proxy note for template publishers:** to make the `EXTERNAL` listener advertise a public endpoint, enable Railway's **TCP proxy** on the broker service's `9093` port. Railway injects `RAILWAY_TCP_PROXY_DOMAIN` / `RAILWAY_TCP_PROXY_PORT`, which the broker entrypoint uses as the advertised address. Without it, `EXTERNAL` falls back to the private domain so the broker still advertises a routable (in-project) address rather than an empty string.
