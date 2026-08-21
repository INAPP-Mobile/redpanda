![Redpanda logo](https://raw.githubusercontent.com/INAPP-Mobile/redpanda/master/template-icon.svg)

<h1 align="center">Redpanda + Console</h1>
<p align="center"><strong>High-performance Kafka API streaming platform with web console, on Railway</strong></p>
<p align="center">
    <a href="https://railway.com/deploy/redpanda-1"><img src="https://railway.app/button.svg" alt="Deploy on Railway" height="40"/></a>
  </p>
  <br/>

# Deploy and Host

**Redpanda** (Kafka-compatible streaming data platform) with **Redpanda Console** (web UI) on Railway. Single click spins up both services with internal networking already wired — no broker env-var hunting, no manual listener configuration.

## About Hosting

Redpanda is a Kafka-compatible streaming data platform written in C++. It's a drop-in replacement for Apache Kafka with lower latency, simpler ops, and no ZooKeeper dependency. This template deploys a single-node Redpanda broker with a web-based management console so you can inspect topics, produce/consume messages, and monitor schemas from one UI.

## Why Deploy

Self-hosting Redpanda on Railway gives you full control over your streaming data. Run event-driven architectures, real-time pipelines, or CQRS/ES systems without the operational overhead of managing Kafka clusters. The broker runs a single-node KRaft cluster (no external ZooKeeper), and the console connects to it automatically over the private network — just open the web UI and start streaming.

## Common Use Cases

- Event-driven microservices with async message passing
- Real-time analytics pipelines and data ingestion
- Change data capture (CDC) from databases to downstream consumers
- CQRS/Event Sourcing systems with append-only streams
- IoT telemetry and time-series data ingestion
- Replacing managed Kafka services to reduce cost and egress

## Dependencies for Redpanda + Console

### Deployment Dependencies

Railway builds both services from their Dockerfiles (`Dockerfile` for console, `broker/Dockerfile` for broker). The broker mounts a persistent Railway volume at `/var/lib/redpanda/data` — topic log segments and KRaft metadata survive restarts and deploys (no data loss across reboots). All credentials and connection strings are auto-generated via Railway placeholders (`${{broker.RAILWAY_PRIVATE_DOMAIN}}`, `${{RAILWAY_PUBLIC_DOMAIN}}`).

## Features

- **Kafka wire-compatible** — drop-in replacement for Apache Kafka with the Kafka protocol.
- **Dual named listeners** — an `INTERNAL` listener over the Railway private network (for Console + same-project services) and an `EXTERNAL` listener exposed to the internet through **Railway's L4 (raw TCP) proxy**.
- **Auto-configured broker** — single-node KRaft, no manual setup. Internal + external listeners resolve from runtime env (private domain + TCP-proxy vars).
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

```javascript
// kafkajs — produce to the EXTERNAL (public) TCP endpoint in ~30 seconds
const { Kafka } = require('kafkajs');

const kafka = new Kafka({
  clientId: 'railway-redpanda-demo',
  brokers: ['<RAILWAY_TCP_PROXY_DOMAIN>:<RAILWAY_TCP_PROXY_PORT>'],
});

const producer = kafka.producer();
const consumer = kafka.consumer({ groupId: 'railway-demo-group' });

async function run() {
  await producer.connect();
  await consumer.connect();

  // Auto-topic creation is on — produce to any topic immediately
  await producer.send({
    topic: 'my-topic',
    messages: [
      { key: 'hello', value: 'from Railway Redpanda!' },
      { key: 'ts', value: new Date().toISOString() },
    ],
  });
  console.log('[producer] sent 2 messages');

  await consumer.subscribe({ topic: 'my-topic', fromBeginning: true });
  await consumer.run({
    eachMessage: async ({ message }) => {
      console.log(`[consumer] ${message.key}: ${message.value}`);
      process.exit(0); // demo: exit after first batch
    },
  });
}

run().catch(console.error);
```

## Environment

### Console (root service)

| Variable | Default | Notes |
|----------|---------|-------|
| `KAFKA_BROKERS` | `broker.railway.internal:9092` | Bootstrap servers. Points at the sibling `broker` service (INTERNAL listener) over the private network. |
| `SCHEMA_REGISTRY_URL` | `http://broker.railway.internal:8081` | Enables per-topic schema views. Leave empty to disable. |

The broker (`broker/`) service is fully auto-configured via hardcoded ENV defaults in `broker/Dockerfile` — single-node KRaft, dual listeners, health shim on `:8080`. No deploy-form variables needed.

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
 │   ┌─────────────────────┐       ┌──────────────────────┐     │
 │   │     broker          │       │     console          │     │
 │   │                     │       │                      │     │
 │   │  INTERNAL :9092 ◄───┼───►   │  KAFKA_BROKERS       │     │
 │   │  EXTERNAL :9093     │       │  SCHEMA_REGISTRY_URL  │     │
 │   │  Schema  :8081  ◄───┼───►   │                      │     │
 │   │  Health  :8080      │       │  HTTP :8080  ◄──► public     │
 │   │  Admin   :9644      │       │                      │     │
 │   └─────────────────────┘       └──────────────────────┘     │
 │                                                              │
 └──────────────────────────────────────────────────────────────┘
             ▲
             │ Railway L4 TCP proxy (EXTERNAL listener)
             ▼
     Internet Kafka clients
```

- **INTERNAL listener** (`:9092`) — binds `0.0.0.0:9092`, advertises `broker.railway.internal:9092`. Used by the Console and any same-project service.
- **EXTERNAL listener** (`:9093`) — binds `0.0.0.0:9093`, advertises the Railway TCP-proxy endpoint (`RAILWAY_TCP_PROXY_DOMAIN:RAILWAY_TCP_PROXY_PORT`) so internet Kafka clients can reach it.
- **Schema Registry** (`:8081`) — built into the broker, used by Console for per-topic schema views.
- **Health shim** (`:8080`) — Perl script reflecting `/v1/status/ready` on the Admin API. Railway's healthcheck hits this port.
- **Admin API** (`:9644`) — internal only, used by the health shim.

## Configuration Reference

| Setting | Value | Notes |
|---------|-------|-------|
| Redpanda image | `redpandadata/redpanda:v26.1.16` | Pinned stable release. |
| Console image | `redpandadata/console:latest` | Tracks upstream latest. |
| Broker smp | 1 | Tuned for small Railway instances. |
| KRaft mode | single-node | No external ZooKeeper needed. |
| Auto-topic creation | enabled | Produce to any topic immediately. |
| Console healthcheck | `/health` (port 8080) | Gated on broker reachability. |

## See Also

- [Redpanda docs](https://docs.redpanda.com/)
- [Redpanda Console docs](https://docs.redpanda.com/current/console/)
- [Railway TCP proxy](https://docs.railway.app/deploy/tcp-proxying)
