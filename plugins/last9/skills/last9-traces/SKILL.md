---
name: last9-traces
description: Guided trace investigation and tracejson query reference for Last9. Interviews the user with 5 targeted questions (service, environment, time window, symptom, scope), fires the right tool call, and carries the reference card for get_traces tracejson pipelines. Use when investigating a trace issue, debugging a service, building or fixing a tracejson query, or when user says "diagnose" / "investigate" / "what's wrong with".
compatibility: Requires the Last9 MCP server (last9-mcp-server) connected to the session
metadata:
  author: last9
---

# last9-traces — trace investigation + tracejson reference

Extends the `get_traces`, `get_service_traces`, and `get_trace_attributes` tool instructions — read those first. This skill carries the investigation flow (which question, which tool, in what order) and the query reference (operators, field syntax, common mistakes).

**Operating principle: progressive narrowing, assisted.** At every step, surface the narrowing handles the data offers — services, environments, trace attributes — and let the user pick. Never guess scope; never go broad when a narrowing option exists.

## Prerequisites

Requires the [Last9 MCP server](https://github.com/last9/last9-mcp-server) connected to this session. If `get_traces`, `get_service_traces`, or `get_trace_attributes` are not available as tools, **stop** — tell the user to install and authenticate the Last9 MCP server first, and link them to the README above. Never fabricate or simulate these tool calls.

## Tool parameters at a glance

For agents consuming this skill outside Claude Code (copy-pasted into a custom system prompt), this is the minimum parameter surface; the MCP tool descriptions remain authoritative.

| Tool | Purpose | Key params |
|------|---------|-----------|
| `get_trace_attributes` | Discover available trace field names (`filter_field`) | time params |
| `get_traces` | Filter / aggregate via tracejson pipeline | tracejson pipeline, time params |
| `get_service_traces` | Service-scoped traces or a specific trace | `service`, optional `trace_id`, time params |

**Time params (every tool):** `lookback_minutes` for relative windows, or `start_time_iso` + `end_time_iso` for explicit ranges — see Time discipline below.

## Attributes first — strict sequence

Discovery and query are strictly sequential: call `get_trace_attributes`, wait for its results, then build the query from the `filter_field` values it returned — never fire discovery and `get_traces` in the same response. Attribute names vary per service with no error on a wrong guess (`attributes['http.status_code']` on one service, `attributes['status_code']` on another) — the filter silently returns zero results. Verify the name via discovery before filtering on it.

## Time discipline

`lookback_minutes` or `start_time_iso` + `end_time_iso` are **top-level tool params**.

- **Relative requests** ("last 15 minutes", "past hour") → `lookback_minutes`. Never fabricate fixed timestamps for a relative request — a generated "now" is wrong by the time the query runs and silently shifts the window.
- **Explicit dates** → `start_time_iso` / `end_time_iso` in RFC3339/ISO8601 UTC, e.g. `2026-06-08T10:00:00Z`. Legacy `YYYY-MM-DD HH:MM:SS` is compatibility-only — do not generate it.
- **Both present** (explicit range plus a relative phrase) → explicit timestamps win; drop `lookback_minutes`.

## Guided investigation — 5 questions

Ask one at a time. For each question, provide your recommended answer based on context already in the conversation; if the conversation already answers a question, skip it and state what you inferred.

**Q1 — Service**
"Which service are you investigating?"
→ If the user named a service loosely, resolve it with `did_you_mean` (`type: service`). If they can't name one, don't ask blind — surface candidates: a `get_traces` aggregate counting traces by `ServiceName` (symptom-filtered when there is one) and let them pick.

**Q2 — Environment**
"Which environment? (e.g. production, staging) — I'll look up the exact attribute name."
→ Call `get_trace_attributes` to find the deployment environment field. Use the returned `filter_field` verbatim for the environment condition.

**Q3 — Time window**
"When did you first notice the issue? Give a relative window ('last 15 minutes') or absolute start/end times."
→ Map the answer per Time discipline above: relative → `lookback_minutes`; absolute → `start_time_iso` / `end_time_iso`.

**Q4 — Symptom**
"What are you seeing — errors, high latency, a specific operation failing, or something else?"
→ Map to: `StatusCode = STATUS_CODE_ERROR` for errors; `Duration > <threshold>` for latency; `SpanName $contains <name>` for a specific operation.

**Q5 — Scope**
"Do you have a specific trace ID to look at, or should we search broadly?"
→ Specific trace ID → use `get_service_traces` with `trace_id`.
→ Broad search → use `get_traces` with a tracejson pipeline built from Q1–Q4 answers.

After Q5, immediately execute the tool call — no confirmation step.

## tracejson reference

## Operator quick reference

**Comparison** (value must be a string):
`$eq` `$neq` `$gt` `$gte` `$lt` `$lte`

**String match**:
`$contains` `$notcontains` `$icontains` `$inotcontains`
`$containsWords` `$notcontainsWords` `$icontainsWords` `$inotcontainsWords`
`$regex` `$notregex` `$iregex` `$inotregex`
`$ieq` `$ineq`

**Existence**: `$exists` `$notnull`

**Logical**: `$and` `$or` `$not`

Form: `{"$op": [field, value]}` — field is always the first element.

## Field mapping priority

Call `get_trace_attributes` to get the exact `filter_field` for any resource or span attribute. Use `filter_field` verbatim — never transform it.

| Situation                       | filter_field to use                        |
|---------------------------------|--------------------------------------------|
| `resource_service.name`         | `ServiceName`                              |
| `resource_<key>`                | `resources['<key>']`                       |
| `event_<key>`                   | `events['<key>']`                          |
| known top-level field           | field name as-is (no brackets)             |
| `grpc.status_code`              | `attributes['rpc.grpc.status_code']`       |
| anything else                   | `attributes['<raw>']`                      |

Top-level fields: `TraceId` `SpanId` `ServiceName` `SpanName` `SpanKind` `StatusCode` `StatusMessage` `Duration` `Timestamp` `ParentSpanId` `TraceState`

## Common mistakes

| Wrong                                      | Correct                                        |
|--------------------------------------------|------------------------------------------------|
| `"resource_department"`                    | `"resources['department']"`                    |
| `"ResourceAttributes.department"`          | `"resources['department']"`                    |
| `"SpanAttributes.http.method"`             | `"attributes['http.method']"`                  |
| `resources["key"]` (double quotes)         | `resources['key']` (single quotes)             |
| `{"ServiceName": "checkout"}`              | `{"$eq": ["ServiceName", "checkout"]}`         |
| `{"function": "count", "alias": "n"}`      | `{"function": {"$count": []}, "as": "n"}`      |
| `"aggregations": [...]`                    | `"aggregates": [...]`                          |
| `"group_by": {...}`                        | `"groupby": {...}`                             |
| `{"$eq": ["StatusCode", "ERROR"]}`         | `{"$eq": ["StatusCode", "STATUS_CODE_ERROR"]}` |
| `{"$eq": ["SpanKind", "SERVER"]}`          | `{"$eq": ["SpanKind", "SPAN_KIND_SERVER"]}`    |

**Failure modes differ by mistake class.** Field-ref, quoting, and pipeline-key mistakes are rejected with corrective errors (the API tells you the right form). Enum-value mistakes are NOT: a wrong `StatusCode` or `SpanKind` value silently returns zero results with no error. If a StatusCode/SpanKind filter comes back empty, check the value against the `STATUS_CODE_*` / `SPAN_KIND_*` forms before trusting the empty result. Numeric values: strings are the guaranteed form; raw numbers are tolerated.

## Related skills

This skill owns **trace-first** investigation and tracejson query craft. For log-first work (log search, log aggregation, logjson pipelines), use `last9-logs`. On an ambiguous debugging prompt, the logs skill takes the logs path and refers trace work here — symmetrically, refer log questions there; do not attempt logjson queries from this skill.
