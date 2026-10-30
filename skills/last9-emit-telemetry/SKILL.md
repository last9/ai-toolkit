---
name: last9-emit-telemetry
description: Emit isolated, attributable Last9 OTLP metrics, logs, and traces for testing alerts, investigations, service profiles, and correlation. Use when generating synthetic Last9 telemetry, running telemetrygen against a Last9 OTLP endpoint, seeding an acceptance_run, or verifying that test signals are queryable — not for creating alerts, rules, dashboards, or production instrumentation.
compatibility: Requires telemetrygen (or equivalent) locally, a user-authorized local OTLP credential file, and the Last9 MCP server for readback
metadata:
  author: last9
---

# last9-emit-telemetry — isolated Last9 OTLP test telemetry

Emit a short, bounded burst of synthetic metrics, logs, and/or traces into an **explicit** Last9 org so agents can test alerts, investigations, service profiles, and correlation. Every signal carries a generated `acceptance_run` UUID. This skill never creates or mutates alerts, rules, dashboards, or deployments.

**Operating principle: isolate, attribute, then prove queryability.** OTLP client success is not Last9 acceptance. Do not claim the run landed until a readback query against the **intended datasource** finds the run ID.

## Prerequisites

Stop unless all of these are present:

1. **Explicit target** — the user named the org/environment (for example Alpha, staging, or a named demo tenant). Do not infer a substitute org from an unrelated MCP session.
2. **User-authorized credential reference** — a **local file path**, or an **environment variable name whose value is that path**. Never accept, print, persist, or echo plaintext tokens, `Authorization` values, or `--otlp-header` contents.
3. **Intended datasource identifier** — the metrics datasource (and log/trace index if the user named one) that readback must query. Do not guess.
4. **`telemetrygen`** on `PATH` (or an equivalent generator that honors the same attribute and endpoint rules). Install with `go install github.com/open-telemetry/opentelemetry-collector-contrib/cmd/telemetrygen@v0.163.0`.
5. **Last9 MCP** connected to the **same** org for readback (`prometheus_*`, `get_logs`, `get_traces`). If those tools are missing, emit may still run, but you must not claim queryability.

If the working tree is this repository, run the helper instead of hand-rolling `telemetrygen` (it normalizes endpoints, quotes attributes, and suppresses header logs):

```bash
scripts/last9-emit-telemetry.sh \
  --org <org-slug> \
  --environment <environment> \
  --credential-file <local-credential-file> \
  --datasource <datasource-id> \
  --signals metrics,logs,traces
```

`--credential-env LAST9_OTLP_CREDENTIAL_FILE` is also valid when that variable holds a **path**. Credential files stay local and untracked. Allowed keys only: `OTEL_EXPORTER_OTLP_ENDPOINT` / `OTLP_ENDPOINT` and `OTEL_EXPORTER_OTLP_HEADERS` / `OTLP_HEADERS`. Do not `cat`, `echo`, or commit the file.

## Anti-pattern checklist

| # | Anti-pattern | Do this instead |
|---|--------------|-----------------|
| 1 | Accepting a pasted token / `--otlp-header` / printing `OTEL_EXPORTER_OTLP_HEADERS` | Take a file path or env **name**; source inside a subshell with `set +x`; never pass `--otlp-header` |
| 2 | `telemetrygen --otlp-endpoint https://host:443/` (gRPC) | Normalize to `host:port`: strip `https://` / `http://` and trailing `/` before invoking |
| 3 | Showing telemetrygen config output (it logs exporter headers by default) | Capture stdout/stderr and drop credential-shaped lines; never `set -x` |
| 4 | Emitting without `acceptance_run` | Generate a UUID first; set resource `service.name` + `acceptance_run` and signal-level `acceptance_run` |
| 5 | Long/unbounded generate (`--duration inf`, `--rate 0`) | Default **5s**, **rate 1**, **workers 1**; refuse inf/unlimited |
| 6 | Creating alerts, recording rules, dashboards, or deploy config as part of emit | Out of scope. Alert creation, rule mutation, and deployment need **separate user authorization** |
| 7 | "Export succeeded, so Last9 has it" | Distinguish **OTLP client export** from **queryable in Last9**; claim the latter only after readback finds the run ID |
| 8 | Retrying the write / duplicating resources when readback is empty | Classify the miss; do not emit again |

## Workflow

1. **Confirm target + credential reference + datasource.** State org, environment, signals, duration/rate, service name (`last9-emit-telemetry` unless the user named one), credential **path**, and datasource. For a production target, get an extra explicit yes. Do not dump the credential file.
2. **Generate `acceptance_run`.** One UUID for the whole run. Refuse to emit if it is missing or not a UUID.
3. **Normalize the endpoint from the credential file** (do not print headers). telemetrygen gRPC wants `host:port`.
4. **Emit** via the helper when present. Otherwise recreate the same wrapper: subshell, `set +x`, headers only in `OTEL_EXPORTER_OTLP_HEADERS`, **no** `--otlp-header`, capture output, suppress credential-shaped lines. Repeat once per signal:

```bash
telemetrygen <metrics|logs|traces> \
  --otlp-endpoint '<host:port>' \
  --duration 5s --rate 1 --workers 1 \
  --service 'last9-emit-telemetry' \
  --otlp-attributes 'service.name="last9-emit-telemetry"' \
  --otlp-attributes 'acceptance_run="<uuid>"' \
  --telemetry-attributes 'acceptance_run="<uuid>"'
```

For metrics, also set `--otlp-metric-name last9.emit.telemetry`. Use `--otlp-insecure` only for localhost plaintext; Last9 `:443` endpoints stay on TLS.

5. **Print a receipt** with only non-secret IDs/config: `acceptance_run`, org, environment, signal types, metric names, `service.name`, start/end UTC, intended datasource, `otlp_export` (`client_ok` / `client_failed`), `last9_queryable` (`no` until readback). Never include headers, tokens, file contents, or raw generator config.
6. **Readback against the intended datasource** — see below. One or two **read** polls are allowed; never a second write.
7. **Classify a miss; do not retry emit.** Then give cleanup guidance without deleting anything.

## Readback — export is not acceptance

`otlp_export=client_ok` means the generator process exited 0. **Queryable in Last9** requires a hit for `acceptance_run` on the intended datasource.

| Signal | Readback (same org, window covering the emit) |
|--------|-----------------------------------------------|
| metrics | `prometheus_instant_query` / `prometheus_range_query` with `datasource` set, e.g. `{acceptance_run="<uuid>"}`. Discover `__name__` if `last9.emit.telemetry` vs `last9_emit_telemetry` is unclear |
| logs | `get_logs` filter on `attributes['acceptance_run']` or `resources['acceptance_run']` (confirm via `get_log_attributes_for_pipeline`). Follow `last9-logs` |
| traces | `get_traces` filter on `attributes['acceptance_run']` or `resources['acceptance_run']`. Follow `last9-traces` |

If MCP is connected to a **different** org than `--org`, treat that as routing, not propagation.

**On empty or failed readback**, pick one class and stop (no second emit):

| Class | When |
|-------|------|
| `ingestion_propagation` | Client export succeeded; the query itself succeeded; window covers the emit; datasource/org match; no series/rows yet |
| `wrong_datasource_or_routing` | Query succeeded but org mismatch, datasource mismatch, or `list_datasources` shows a different intended TSDB/index than the one queried |
| `query_path_timeout` | The read call timed out, 5xx'd, or the MCP tool failed — this does **not** prove absence |

## Cleanup (manual only)

Do not delete telemetry, datasources, alerts, or files automatically. Tell the user they can identify leftovers by `acceptance_run` / `service.name=last9-emit-telemetry`, that ingested points age out with retention, and that any local temp files the helper created can be removed by them. Leave credential files untouched.

## Related skills

- `last9-logs` / `last9-traces` — query-side investigation after this run is queryable.
- Alerting, recording rules, dashboard writes, collector deploys, and production config changes are **not** this skill. Those require a separate, explicit user authorization.
