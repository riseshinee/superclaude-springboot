---
name: sb-perf-ops
description: Use this skill when diagnosing Spring Boot production/runtime performance and operations issues — JVM memory/GC tuning, HikariCP connection pool sizing, caching strategy (Caffeine/Redis), Actuator/Micrometer observability, graceful shutdown, or container resource limits. Triggers on "tune the production environment", "memory issue", "GC problem", "connection pool", "deployment/health check", "OOM", "it's slow in production" or similar production performance questions.
---

# Spring Boot Production/Operations Diagnostics

Diagnose production performance issues and provide both likely causes and concrete configuration values. Avoid speculative tuning — always pair advice with what to measure to confirm it.

## HikariCP connection pool

- Rule of thumb: `connections = ((core_count * 2) + effective_spindle_count)`. Most web applications should start small based on CPU core count (e.g., 10–20) and adjust based on load testing. Blindly increasing pool size just increases DB connection contention.
- Things to check:
  - Does `spring.datasource.hikari.maximum-pool-size` exceed the DB server's `max_connections` once you account for all application instances × their pool sizes?
  - If `connection-timeout` errors (`Connection is not available`) appear in logs, that's pool exhaustion — usually caused by slow queries/transactions holding connections too long, not an undersized pool. Set `leak-detection-threshold` first to rule out connection leaks.
  - Measure with Actuator's `/actuator/metrics/hikaricp.connections.active` and `hikaricp.connections.pending`.

## JVM memory / GC

- In containerized environments, prefer a ratio-based setting like `-XX:MaxRAMPercentage=75.0` over a fixed `-Xmx`, so the heap auto-scales with the container's memory limit. (Confirm JDK 11+ is used — older JVMs may not recognize cgroup limits.)
- The default GC is G1GC (default since JDK 9). For latency-sensitive API servers, stick with G1GC and tune `-XX:MaxGCPauseMillis`; for throughput-oriented batch jobs, Parallel GC is worth evaluating.
- Diagnostic order for frequent OOM/Full GC:
  1. Check Full GC frequency and reclaimed size via GC logs (`-Xlog:gc*`).
  2. Take a heap dump (`-XX:+HeapDumpOnOutOfMemoryError`) to see what's actually occupying the heap — large caches, sessions, or unbounded collections are common culprits.
  3. Look at the actual heap composition before guessing at application code causes.
- `MetaspaceOutOfMemoryError` is usually caused by a classloader leak (dynamic proxies/reflection-heavy libraries, frequent hot-redeploys), not something GC tuning fixes — find the leak source instead.

## Caching

- For an in-process cache on a single instance where low latency matters: Caffeine + `@Cacheable`. Always set `maximumSize`/`expireAfterWrite` to prevent unbounded growth.
- If cache sharing across multiple instances is needed, use Redis. To avoid cache stampedes (many keys expiring at once and flooding the origin), add jitter to TTLs or serialize cache warming with a distributed lock.
- Before adding a cache, confirm how often the data is read versus how often it changes — caching frequently-written data just adds invalidation complexity without much benefit.

## Observability (Actuator / Micrometer)

- Expose a minimal set of endpoints: `health`, `info`, `metrics`, `prometheus` (don't expose everything — list only what's needed under `management.endpoints.web.exposure.include`).
- Set `management.endpoint.health.probes.enabled=true` to split `/actuator/health/liveness` and `/actuator/health/readiness` for Kubernetes probes.
- Recommend dashboarding request latency distribution (p50/p95/p99), error rate, GC time, and connection pool utilization via Micrometer + Prometheus/Grafana.

## Graceful shutdown / deployment

- Set `server.shutdown=graceful` plus `spring.lifecycle.timeout-per-shutdown-phase` so in-flight requests finish before shutdown — essential for zero-downtime/rolling deploys.
- On Kubernetes, use a `preStop` hook (e.g., a short sleep) to give the load balancer time to stop routing traffic before the pod actually shuts down, and make sure the readiness probe fails first.
- Verify the container's `limits.memory` is consistent with the JVM's `-XX:MaxRAMPercentage` — requesting more heap than the limit allows leads to OOMKilled.

## Always ask first, before prescribing

Before giving a specific fix, confirm the following with the user if missing:
- When and under what conditions did the symptom start (right after a deploy? at a traffic spike? on a specific endpoint?)
- Is there measured data available — GC logs, heap dumps, Actuator metrics — and if not, guide how to collect it first.
- Deployment environment details: instance count, container resource limits, DB specs.
