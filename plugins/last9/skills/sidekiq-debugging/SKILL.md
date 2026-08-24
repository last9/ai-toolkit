---
name: sidekiq-debugging
description: Debug Sidekiq/ActiveJob background jobs through Last9 telemetry — failing jobs, retry storms, slow jobs, queue backlog, and alerting on job health. Carries the Rails job span anatomy (dual ActiveJob+Sidekiq instrumentation, job identity/dedup keys) and named, validated tracejson/PromQL recipes. Use when investigating background job issues or when user says "jobs failing", "sidekiq", "background jobs", "queue backed up", "retry storm", or wants alerts on job failures.
compatibility: Requires the Last9 MCP server (last9-mcp-server) connected to the session
metadata:
  author: last9
---

# sidekiq-debugging — background job investigation via Last9

Debugs Rails background jobs (Sidekiq, via ActiveJob or bare) through telemetry alone — traces first, logs and trace-derived metrics where they fit. No application or Redis access assumed.

**Operating principle: identity before counting.** Pick the identity level first — job class, job instance, or execution attempt — and the query follows. Counts at the wrong level inflate or deflate with no error to warn you.

## Prerequisites

Requires the [Last9 MCP server](https://github.com/last9/last9-mcp-server) connected to this session. If `get_traces`, `get_trace_attributes`, or `prometheus_instant_query` are not available as tools, **stop** — tell the user to install and authenticate the Last9 MCP server first. Never fabricate or simulate these tool calls.

For tracejson operator syntax, field mapping, and common mistakes, defer to the `last9-traces` skill — this skill only carries Sidekiq-specific knowledge on top of it.

## Applicability check — run this FIRST

This skill triggers on generic phrases ("jobs failing", "queue backed up") that also describe Kafka, SQS, Celery, and other job systems. Before using any recipe, verify the target service actually runs Sidekiq:

```json
[
  {"type": "filter", "query": {"$and": [
    {"$eq": ["ServiceName", "<your-service>"]},
    {"$eq": ["SpanKind", "SPAN_KIND_CONSUMER"]}
  ]}},
  {"type": "aggregate",
   "groupby": {"attributes['messaging.system']": "messaging_system"},
   "aggregates": [{"function": {"$count": []}, "as": "spans"}]}
]
```

- `sidekiq` and/or `active_job` present → proceed with this skill.
- Neither present (e.g. only `kafka`, `aws_sqs`, or empty) → **stop using this skill.** Tell the user the service does not emit Sidekiq/ActiveJob spans and route the investigation through `last9-traces` instead. Do not adapt these recipes to other messaging systems — the anatomy (dual spans, dedup keys) is Sidekiq-specific and will mislead.
- A service can show multiple systems (e.g. `kafka` + `sidekiq`); recipes still apply to its sidekiq/active_job spans.
- The gate reads consumer spans only — a system that appears solely on the producer side (e.g. the service publishes to Kafka but never consumes it) won't show up, and doesn't affect applicability.

## Symptom router

| User says | Section | Recipes |
|---|---|---|
| "jobs are failing" / "alert on job failures" | Jobs failing | R1, R2, R3 |
| "same job keeps retrying" / "retry storm" | Retry storms | R4 |
| "jobs are slow" / "worker latency" | Slow jobs | R5 |
| "queue backed up" / "jobs not processing" | Queue backlog | R6 |
| "job disappeared" / "dead set" | Known gaps | — |

## Sidekiq trace anatomy

Read this before running any recipe. Every fact here comes from live production traces, not framework docs.

### Dual instrumentation — every execution emits TWO consumer spans

Rails apps instrumented with OTel emit one span from the ActiveJob layer AND one from the Sidekiq adapter layer for the *same* job execution. Both are `SPAN_KIND_CONSUMER`; both get `STATUS_CODE_ERROR` on failure.

| Layer | `messaging.system` | Instance ID attribute | Notes |
|---|---|---|---|
| ActiveJob | `active_job` | `messaging.message.id` = ActiveJob job_id (UUID) | also carries `messaging.active_job.message.provider_job_id` = Sidekiq JID |
| Sidekiq | `sidekiq` | `messaging.message_id` = Sidekiq JID | also carries `messaging.sidekiq.job_class` |

The cross-link: the ActiveJob span's `provider_job_id` equals the Sidekiq span's `messaging.message_id`.

**Rule: every job query MUST pin one layer** with `{"$eq": ["attributes['messaging.system']", "active_job"]}` (or `"sidekiq"`). Unpinned queries double-count everything.

### Job identity taxonomy — three levels

1. **Job class** — e.g. `Billing::ChargeJob`. Lives in `SpanName`, formatted `<queue> process <JobClass>` (e.g. `default process Billing::ChargeJob`). Same class on two queues = two SpanNames.
2. **Job instance** — one enqueued job with specific arguments. Two IDs exist:
   - `messaging.message.id` (ActiveJob job_id, on `active_job` spans) — survives Sidekiq native retries AND `retry_on` re-enqueues. **Strongest instance identity; prefer it.**
   - `messaging.message_id` (Sidekiq JID, on `sidekiq` spans) — survives Sidekiq native retries only; `retry_on` mints a fresh JID, so re-enqueues count as new instances.
3. **Execution attempt** — each retry produces a fresh pair of consumer spans. Raw error-span counts measure attempts, not instances.

### Other facts that bite

- `Duration` is **nanoseconds** (`313200779` ≈ 313ms).
- `StatusCode`/`SpanKind` take enum forms (`STATUS_CODE_ERROR`, `SPAN_KIND_CONSUMER`); wrong values return empty results with **no error** — see `last9-traces` for the full table.
- Enqueue side is instrumented too: `SPAN_KIND_PRODUCER` spans with `messaging.destination` = queue name on both layers.
- Queue name is available as `attributes['messaging.destination']` on both producer and consumer `sidekiq`-layer spans, and as the `SpanName` prefix.

## Jobs failing

### R1: unique-job-classes-failing (PromQL, alertable directly)

**When:** "how many *different* jobs are failing" — distinct classes, not failure volume. One class failing 100× counts as 1.

Last9 derives `trace_endpoint_count` from spans with `span_name`, `span_kind`, `status_code` labels. It is a **per-window gauge**, not a counter — use `sum_over_time`, never `rate()`/`increase()` (see the `last9-trace-metrics` skill):

```promql
count(
  sum by (span_name) (
    sum_over_time(trace_endpoint_count{
      service_name="<your-service>",
      span_kind="SPAN_KIND_CONSUMER",
      status_code="STATUS_CODE_ERROR"
    }[5m])
  ) > 0
)
```

Inner `sum by (span_name) ... > 0` keeps only classes with ≥1 failure; outer `count` counts classes. To dedupe job class across queues (SpanName carries the queue prefix):

```promql
count(
  sum by (job_class) (
    label_replace(
      sum_over_time(trace_endpoint_count{service_name="<your-service>", span_kind="SPAN_KIND_CONSUMER", status_code="STATUS_CODE_ERROR"}[5m]),
      "job_class", "$1", "span_name", ".+ process (.+)"
    )
  ) > 0
)
```

**Gotcha:** the trace-derived metric path counts classes only — instance IDs are span attributes and never become metric labels (cardinality).

### R2: unique-job-instances-failing (tracejson)

**When:** distinct job *instances* failing — one stuck instance retrying 25× counts as 1; 100 different instances of one class count as 100.

Chained aggregates emulate `COUNT(DISTINCT ...)`:

```json
[
  {"type": "filter", "query": {"$and": [
    {"$eq": ["ServiceName", "<your-service>"]},
    {"$eq": ["SpanKind", "SPAN_KIND_CONSUMER"]},
    {"$eq": ["StatusCode", "STATUS_CODE_ERROR"]},
    {"$eq": ["attributes['messaging.system']", "active_job"]}
  ]}},
  {"type": "aggregate",
   "groupby": {"attributes['messaging.message.id']": "job_instance", "SpanName": "job_class"},
   "aggregates": [{"function": {"$count": []}, "as": "attempts"}]},
  {"type": "aggregate",
   "groupby": {"job_class": "job_class"},
   "aggregates": [{"function": {"$count": []}, "as": "unique_failing_instances"}]}
]
```

Drop `job_class` from the final `groupby` for a single org-wide number. Add a `$contains` SpanName condition to scope to one job family.

**Gotchas:** dedup is window-scoped — an instance failing in two separate query windows counts twice. The `sidekiq` layer + `messaging.message_id` variant gives identical results until `retry_on` re-enqueues occur (then it overcounts).

### R3: instance-failure-alert (wiring)

R2's tracejson can't be a PromQL alert indicator directly. Path: **scheduled search → metric → alert**.

1. Save R2 as a scheduled search rule (eval every 1m, trailing 5m window) emitting a counter metric, e.g. `unique_failing_job_instances` (labeled by `job_class` if R2 keeps the per-class groupby)
2. Alert on the emitted metric with threshold `> N`; pick the alert window in Alert Studio

Class-level alerting (R1) needs no scheduled search — alert on the PromQL directly. Prefer R1 unless retry inflation genuinely distorts your signal (measure first: run R2's middle stage and compare attempts vs instances).

## Retry storms

### R4: instances-stuck-retrying

**When:** find specific instances burning retries. Post-aggregate `filter` acts as SQL `HAVING`:

```json
[
  {"type": "filter", "query": {"$and": [
    {"$eq": ["ServiceName", "<your-service>"]},
    {"$eq": ["SpanKind", "SPAN_KIND_CONSUMER"]},
    {"$eq": ["StatusCode", "STATUS_CODE_ERROR"]},
    {"$eq": ["attributes['messaging.system']", "active_job"]}
  ]}},
  {"type": "aggregate",
   "groupby": {"attributes['messaging.message.id']": "job_instance", "SpanName": "job_class"},
   "aggregates": [{"function": {"$count": []}, "as": "failed_attempts"}]},
  {"type": "filter", "query": {"$gt": ["failed_attempts", "2"]}}
]
```

Output: each row = one stuck instance with its attempt count. Many rows for one `job_class` = that class is systemically broken; scattered classes = shared dependency failing.

## Slow jobs

### R5: duration-percentiles-by-class

```json
[
  {"type": "filter", "query": {"$and": [
    {"$eq": ["ServiceName", "<your-service>"]},
    {"$eq": ["SpanKind", "SPAN_KIND_CONSUMER"]},
    {"$eq": ["attributes['messaging.system']", "active_job"]}
  ]}},
  {"type": "aggregate",
   "groupby": {"SpanName": "job_class"},
   "aggregates": [
     {"function": {"$quantile": [0.95, "Duration"]}, "as": "p95_ns"},
     {"function": {"$count": []}, "as": "executions"}
   ]}
]
```

**Gotcha:** `Duration` is nanoseconds — divide by 1e9 for seconds before reporting. Low-volume classes (executions < ~20) make p95 noisy; report the count alongside.

## Queue backlog

### R6: enqueue-vs-process-rate

**When:** "is a queue falling behind?" Direct queue depth and enqueue→start latency are NOT derivable from traces (see Known gaps). The proxy: compare producer span rate vs consumer span rate per queue over the same window.

Run twice with `SPAN_KIND_PRODUCER` then `SPAN_KIND_CONSUMER`:

```json
[
  {"type": "filter", "query": {"$and": [
    {"$eq": ["ServiceName", "<your-service>"]},
    {"$eq": ["SpanKind", "SPAN_KIND_PRODUCER"]},
    {"$eq": ["attributes['messaging.system']", "sidekiq"]}
  ]}},
  {"type": "aggregate",
   "groupby": {"attributes['messaging.destination']": "queue"},
   "aggregates": [{"function": {"$count": []}, "as": "spans"}]}
]
```

Enqueued ≫ processed sustained across windows = backlog growing. Roughly equal = keeping up. Use the same lookback for both runs.

**Gotcha:** aggregate output is unordered and result limits truncate silently — a low `limit` can drop the *highest-volume* queues from the comparison (verified live: a limit of 6 hid the three busiest queues out of ~40). Leave the limit unset or set it well above the queue count.

## Known gaps — validated as NOT answerable from telemetry

- **Dead set / retries-exhausted jobs**: Sidekiq does not log job death by default, and no span marks it. Requires an app-side death handler (`config.death_handlers`) that logs or emits a metric. If logs exist, search via the `last9-logs` skill.
- **Enqueue→start latency (true queue latency)**: consumer spans carry no `enqueued_at` attribute, and tracejson cannot join producer and consumer spans. R6's rate comparison is the honest proxy.

Do not improvise recipes for these from priors. Both probes ran against live production telemetry and came back empty.

## Alerting cookbook

| Want | Path | Recipe |
|---|---|---|
| N distinct job classes failing | PromQL on `trace_endpoint_count`, alert directly | R1 |
| N distinct job instances failing | scheduled search → metric → alert | R2+R3 |
| Specific critical job failing at all | R1 PromQL with `span_name` filter, threshold `> 0` | R1 variant |
| Queue falling behind | two scheduled searches (enqueue/process rates) → metric ratio | R6 |

Start with R1 — zero moving pieces. Add the scheduled-search path only when retry noise provably distorts the class-level signal.

## Related skills

This skill owns Sidekiq/ActiveJob-specific debugging. For general tracejson query craft (operators, field mapping, common mistakes), use `last9-traces`. For log-side investigation (death handlers, exception text search), use `last9-logs`.
