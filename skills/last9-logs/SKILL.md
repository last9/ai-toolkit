---
name: last9-logs
description: Query Last9 logs effectively — service-first scoping, attribute filters over body search, aggregate-then-drill. Use when querying or searching Last9 logs, finding log errors, building a get_logs logjson pipeline, or debugging a symptom through logs ("query logs", "find logs", "search logs", "log errors").
compatibility: Requires the Last9 MCP server (last9-mcp-server) connected to the session
metadata:
  author: last9
---

# last9-logs — query Last9 logs effectively

Extends the `get_logs`, `get_service_logs`, and `get_log_attributes` tool instructions — read those first. This skill carries the navigation judgment: which tool when, in what order, and the mistakes that make log queries fail or lie.

**Operating principle: progressive narrowing, assisted.** At every step, surface the narrowing handles the data offers — services, environments, resource attributes — and let the user pick. Never guess scope; never go broad when a narrowing option exists.

## Prerequisites

Requires the [Last9 MCP server](https://github.com/last9/last9-mcp-server) connected to this session. If `get_logs`, `get_service_logs`, or `get_log_attributes` are not available as tools, **stop** — tell the user to install and authenticate the Last9 MCP server first, and link them to the README above. Never fabricate or simulate these tool calls.

## Before any query — anti-pattern checklist

Check every query against these five. Each one names the redirect, not just the mistake.

| # | Anti-pattern | Do this instead |
|---|--------------|-----------------|
| 1 | Global search across all logs | Scope to a service first (`ServiceName` filter, or `get_service_logs`) |
| 2 | Full-text body search for something an attribute covers | Call `get_log_attributes`, filter on the attribute |
| 3 | Pulling raw log lines for a broad symptom | Aggregate first (count by severity / attribute), then drill into the dominant pattern |
| 4 | Pipeline starting with an `aggregate` stage | First stage must be a `filter` — a missing filter is silently treated as match-all, widening scope to every log in the window. Lead with an explicit filter so scope is deliberate |
| 5 | Bare dotted field refs (`service.name`, `k8s.namespace.name`) | `ServiceName` / `attributes['field.name']` / `resources['field.name']` — a few refs (`service.name`, `k8s.*`) are silently normalized as aliases; everything else is rejected. Always write the canonical form |

## Methodology — service first, aggregate first, drill last

Work through these steps in order. Skip a step only when the conversation already answered it.

1. **Establish scope — surface, don't interrogate** — if the user named a service loosely or you suspect a typo, resolve it with `did_you_mean` (`type: service`). If no service is named, don't ask blind: surface the inventory — run a `filter` → `aggregate` `$count` grouped by `ServiceName` (pre-filtered by the symptom when there is one) and present the top candidates for the user to pick from. When multiple environments exist, surface `resources['deployment.environment']` values the same way and confirm which one — include the empty-env bucket explicitly when present, since unset environments often dominate. (Use the aggregate to surface environments; `did_you_mean` coverage for environment names is unreliable.) If the service dimension doesn't discriminate (catch-all service, or none), scope by the next-best dimension attribute discovery surfaces — namespace, host, environment. Never fire an unscoped body search.
2. **Discover attributes — and offer them as narrowing handles** — call `get_log_attributes` to see available log and resource attributes. It is global (time-window scoped, no service param) — service scoping happens in your filter stage, not here. Use it to learn the exact field names before filtering; never guess whether a field lives in `attributes[...]` or `resources[...]`. When scope is still broad, present the discriminating resource attributes (`resources['k8s.namespace.name']`, `resources['k8s.deployment.name']`, `resources['deployment.environment']`, host) as narrowing options the user can pick — an aggregate `$count` grouped by a candidate attribute shows them where their logs actually concentrate. A handle whose buckets split evenly has no narrowing power — pick a different one.
3. **Aggregate to find the pattern** — call `get_logs` with a pipeline: `filter` stage (service + symptom conditions) followed by an `aggregate` stage (e.g., `$count` grouped by `SeverityText` or a suspect attribute). Present the narrowed pattern before pulling raw lines.
4. **Narrow with attribute filters** — tighten the filter stage using the discovered attributes (`$eq`, `$gte` on `attributes['http.status_code']`, etc.).
5. **Drill into raw lines** — call `get_service_logs` (simple: `service`, `severity_filters`, `body_filters`, `limit`) or `get_logs` with the narrowed filter.
6. **Body search — last resort** — `$containsWords` on `Body` only inside the already-narrowed scope, and only for text no attribute covers.

**Time windows:** `lookback_minutes` (default 5) or `start_time_iso` + `end_time_iso` are **top-level tool params** — never write `Timestamp` conditions inside the pipeline for time ranges.

## logjson essentials

A `get_logs` query is a JSON **array of stages**, executed in order: `filter` → `parse` → `aggregate` / `window_aggregate`. Conditions take the form `{"$op": [field, value]}` — field is always the first element.

**Operators:**

| Category | Operators |
|----------|-----------|
| Equality | `$eq` `$neq` `$ieq` `$ineq` |
| Numeric (value is a **string**) | `$gt` `$lt` `$gte` `$lte` |
| Substring | `$contains` `$notcontains` `$icontains` `$inotcontains` |
| Word-boundary (prefer for `Body`) | `$containsWords` `$icontainsWords` |
| Regex | `$regex` `$notregex` `$iregex` `$inotregex` |
| Logical | `$and` `$or` `$not` |

**Fields:** `Body`, `ServiceName` (always prefer over similar attributes), `SeverityText` (DEBUG/INFO/WARN/ERROR/FATAL — may be empty for services that don't set it; aggregate by `SeverityText` before filtering on it, or a severity filter silently returns nothing; when it is empty and bodies are JSON, add a `parse` stage and aggregate by the extracted level field, e.g. `attributes['level']`), `Timestamp`, `attributes['field.name']`, `resources['field.name']`.

**Canonical shapes:**

Service-scoped error search (filter only — no aggregation unless the user asks "how many"):

```json
[{
  "type": "filter",
  "query": {
    "$and": [
      {"$eq": ["ServiceName", "auth"]},
      {"$containsWords": ["Body", "error"]}
    ]
  }
}]
```

Error count by service (aggregate ALWAYS preceded by filter):

```json
[{
  "type": "filter",
  "query": {"$and": [{"$containsWords": ["Body", "error"]}]}
}, {
  "type": "aggregate",
  "aggregates": [{"function": {"$count": []}, "as": "error_count"}],
  "groupby": {"ServiceName": "service"}
}]
```

Rate over time windows:

```json
[{
  "type": "filter",
  "query": {"$and": [{"$neq": ["attributes['endpoint']", ""]}]}
}, {
  "type": "window_aggregate",
  "function": {"$count": []},
  "as": "request_rate",
  "window": ["5", "minutes"],
  "groupby": {"attributes['endpoint']": "endpoint"}
}]
```

**Common mistakes:**

| Wrong | Correct |
|-------|---------|
| `{"$eq": ["service.name", "auth"]}` | `{"$eq": ["ServiceName", "auth"]}` |
| `{"$eq": ["k8s.namespace.name", "prod"]}` | `{"$eq": ["resources['k8s.namespace.name']", "prod"]}` |
| `[{"type": "aggregate", ...}]` as first stage | `filter` stage first, then `aggregate` |
| `{"$contains": ["Body", "error"]}` for word search | `{"$containsWords": ["Body", "error"]}` |
| `{"$gt": ["attributes['http.status_code']", 500]}` | `{"$gt": ["attributes['http.status_code']", "500"]}` (the reference specifies string values; raw numbers are often tolerated, but strings are the guaranteed form) |
| `{"$gte": ["Timestamp", "2026-06-04T00:00:00Z"]}` in pipeline | `start_time_iso` / `end_time_iso` as top-level params |
| `{"ServiceName": "auth"}` | `{"$eq": ["ServiceName", "auth"]}` |
| `"group_by": {...}` / `"aggregations": [...]` | `"groupby": {...}` / `"aggregates": [...]` |

**Silent-failure warning:** misspelled pipeline keys are NOT rejected — they are silently ignored. A `group_by` typo returns an ungrouped total with no error, which reads like a valid answer. Check key spelling against this table before trusting aggregate output.

## Which tool when

| Need | Tool |
|------|------|
| Resolve a fuzzy service name | `did_you_mean` (`type: service`) |
| What attributes exist? | `get_log_attributes` |
| Counts, grouping, rates, complex filters | `get_logs` (logjson pipeline) |
| Quick service-scoped raw lines | `get_service_logs` |

## Related skills

This skill owns **log-first** investigation. For trace-first work (latency breakdowns, span analysis, trace IDs, tracejson queries), use `last9-traces` — guided 5-question trace investigation plus the tracejson reference card. On an ambiguous debugging prompt ("why is checkout failing"), take the logs path here and point the user to `last9-traces` for the trace side; do not attempt trace queries from this skill.

<!--
Grammar verification: all query examples and syntax rules above verified against the
public last9-mcp-server get_logs tool documentation (github.com/last9/last9-mcp-server)
and the authoritative Last9 log query grammar. Verified: 2026-06-04.
-->
