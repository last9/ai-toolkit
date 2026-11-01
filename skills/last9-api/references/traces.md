# Traces query API

Source: Last9 "Traces Query API" documentation. This API queries traces; it does not ingest them.

Paths are relative to the org base. Timestamps are Unix **seconds**. **`region` is required** on the query endpoints (for example `ap-south-1`); omitting it returns 400 `region query parameter is required`. `last9.py api` adds it automatically to `cat/` paths from `LAST9_REGION` or the profile region (`login --region <r>`); an explicit `-q region=` wins. A wrong region gives 500 `ERR_S3_CONFIG_MISSING` or a 502 "Maintenance Mode" page.

## Endpoints

| Method | Path | Purpose |
| ------ | ---- | ------- |
| POST | `/cat/api/traces/v2/query_range/json` | Query spans or traces with a pipeline |
| POST | `/cat/api/traces/v2/search/json` | Search traces with span sets; duration filters |
| GET | `/cat/api/traces/{traceID}` | All spans of one trace (32-char hex ID) |
| POST | `/cat/api/traces/v2/heatmap/json` | Duration heatmap |
| POST | `/cat/api/traces/v2/series/json` | Available tags |
| POST | `/cat/api/traces/v2/label/json/{tagName}/values` | Values for a tag |
| GET/POST/PUT/DELETE | `/traces/searches`, `/traces/searches/{id}` | Saved searches |
| GET | `/traces/recent-searches` | Recent searches (retained 7 days) |

## Query params

Common: `region` (required), `start` (required, s), `end` (required, s).

- query_range: `limit`, `order` (`asc`/`desc`), `direction`, `mode` (`span` or `trace`).
- search: `limit`, `span_limit` (spans per trace), `order`, `mode`, `minDuration` (for example `100ms`, `1s`), `maxDuration`.
- get trace: `limit` (default 1000 spans).
- heatmap: also `time_resolution_sec` (required, x-axis) and `buckets` (required, y-axis).
- saved/recent searches: optional `query_source` = `manual` or `nlp`.

Body for query/search/heatmap: `{"pipeline":[ ... ]}` (use `{"pipeline": []}` for none). Series and tag-values endpoints are POST with body `{}`.

Saved search create body: `name` (required), `pipeline` (required), `mode` (required, `span`/`trace`), `shared` (optional bool, default false).

## Pipeline

```json
{ "type": "filter", "query": { "$and": [ { "$eq": ["service.name", "api-gateway"] }, { "$gte": ["http.status_code", "500"] } ] } }
```

Operators (2-element arrays): `$eq`, `$ieq`, `$neq`, `$ineq`, `$gt`, `$gte`, `$lt`, `$lte`, `$contains`, `$icontains`, `$notcontains`, `$regex`, `$iregex`, `$notregex`. Logical: `$and`, `$or`, `$not`, nestable. `i` variants are case-insensitive; the rest are case-sensitive.

Field prefixes: `resource.` (resource attributes), `span.` (span attributes), none (auto-resolved, for example `service.name`).

Modes: `span` queries individual spans; `trace` queries complete traces.

## Response shapes (trimmed)

query_range: `{"status":"success","data":{"resultType":"stream","result":[{"Timestamp","TraceId","SpanId","ParentSpanId","SpanName","SpanKind","ServiceName","ResourceAttributes":{},"SpanAttributes":{},"Duration":25748892,"StatusCode","StatusMessage"}]}}`. Empty: `"result": []`.

search: result items have `traceID`, `rootServiceName`, `rootTraceName`, `startTimeUnixNano`, `endTimeUnixNano`, `durationMs`, `spanSets`.

get trace: `{"traces":[ ...span objects... ]}`. Tags: `{"status":"success","data":[{"service.name":"...","http.method":"..."}]}`.

Span kinds: `SPAN_KIND_UNSPECIFIED|INTERNAL|SERVER|CLIENT|PRODUCER|CONSUMER`. Status: `STATUS_CODE_UNSET|OK|ERROR`.

## Recipes

```bash
S=$(( $(date +%s) - 3600 )); E=$(date +%s)
# 5xx traces for a service
python3 <skill-dir>/scripts/last9.py api POST cat/api/traces/v2/query_range/json \
  -q region=<region> -q start=$S -q end=$E -q limit=100 -q mode=trace \
  -d '{"pipeline":[{"type":"filter","query":{"$and":[{"$eq":["service.name","api-gateway"]},{"$gte":["http.status_code","500"]}]}}]}'

# Slow traces (1s to 10s)
python3 <skill-dir>/scripts/last9.py api POST cat/api/traces/v2/search/json \
  -q region=<region> -q start=$S -q end=$E -q limit=50 -q minDuration=1s -q maxDuration=10s -d '{"pipeline":[]}'

# One trace
python3 <skill-dir>/scripts/last9.py api GET cat/api/traces/<trace-id> -q region=<region> -q start=$S -q end=$E

# Discover tag values
python3 <skill-dir>/scripts/last9.py api POST cat/api/traces/v2/label/json/service.name/values \
  -q region=<region> -q start=$S -q end=$E -d '{}'
```

## Gotchas

- Seconds here, nanoseconds in the logs API.
- Empty results: check field names (use the tags endpoint), time range, retention, pipeline JSON, and `mode`.
- Documented errors: 400 missing `region`; 401 `Authorization token is expired`; 403 forbidden; 404 not found; 500 `ERR_S3_CONFIG_MISSING` (OTLP configuration not found for org).
- Check the `{org}` slug matches your token's org if you get authorization errors.
