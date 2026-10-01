# Logs query API

Source: Last9 "Logs Query API" documentation. This API queries logs; it does not ingest them.

Base: `/logs/...` relative to the org base (use with `last9.py api`). Timestamps are Unix **nanoseconds**.

## Query logs

```text
POST /logs/api/v2/query_range/json
```

| Param | Type | Required | Description |
| ----- | ---- | -------- | ----------- |
| `start` | int | yes | Start, Unix ns |
| `end` | int | yes | End, Unix ns |
| `limit` | int | no | Max logs |
| `direction` | string | no | `forward` or `backward` |
| `step` | string | no | Time step for aggregations |
| `offset` | int | no | Pagination offset |
| `region` | string | **yes** | Cloud region the org's data lives in (for example `ap-south-1`). The public docs say optional; the API returns 400 `region query parameter is required` without it. |
| `index` | string | no | `physical_index:<name>` or `rehydration_index:<name>` |

Body is a JSON pipeline:

```json
{ "pipeline": [ { "type": "filter", "query": { "$and": [ { "$eq": ["service", "api-gateway"] } ] } } ] }
```

Response (trimmed):

```json
{ "status": "success",
  "data": { "resultType": "streams",
    "result": [ { "stream": { "service": "api-gateway", "level": "error" },
                  "values": [ ["1743505000000000000", "Connection timeout after 30s"] ] } ],
    "stats": { "summary": { "totalLinesProcessed": 1000, "execTime": 0.25 } } } }
```

No matches: `"result": null`.

## Discover labels and values

```text
GET /logs/api/v1/labels                       params: start, end (required, ns)
GET /logs/api/v1/label/{labelName}/values     params: start, end (required, ns)
```

Both also require `region`, and accept seconds as well as ns (verified). Responses: `{"status":"success","data":["service","level",...]}`.

## Pipeline syntax

Stages (`type`): `filter`, `where` (adds conditions, OR/NOT logic), `parse`.

```json
{ "type": "parse", "parser": "json", "field": "body", "labels": { "user_id": null, "request_id": null } }
```

Operators (each takes a 2-element array `["field", "value"]`): `$eq`, `$neq`, `$contains`, `$notcontains`, `$regex`, `$notregex`, `$gt`, `$lt`, `$gte`, `$lte`. Numeric comparisons take string values (`["status_code", "400"]`). Combine with `$and`, `$or`, `$not` (`{"$not": [{"$and": [...]}]}`); logical operators nest.

## Recipes

`last9.py api` adds `region=<r>` to every `logs/` path automatically, from `LAST9_REGION` or the profile region saved by `login --region <r>`; it exits 1 without calling the API if neither is set. The recipes below rely on that; with raw curl add `region=<r>` yourself. A wrong region returns 500 `{"error":"ERR_S3_CONFIG_MISSING"}` or a 502 "Maintenance Mode" HTML page.

Time helper (ns): `$(( $(date +%s) * 1000000000 ))`.

```bash
S=$(( ($(date +%s) - 3600) * 1000000000 )); E=$(( $(date +%s) * 1000000000 ))
python3 <skill-dir>/scripts/last9.py api POST logs/api/v2/query_range/json \
  -q start=$S -q end=$E -q limit=100 -q direction=backward \
  -d '{"pipeline":[{"type":"filter","query":{"$and":[{"$eq":["service","payment-service"]},{"$eq":["level","error"]}]}}]}'
```

Discover labels, then values for one label:

```bash
python3 <skill-dir>/scripts/last9.py api GET logs/api/v1/labels -q start=$S -q end=$E
python3 <skill-dir>/scripts/last9.py api GET logs/api/v1/label/service/values -q start=$S -q end=$E
```

Text search plus OR with a `where` stage: put a `filter` stage for the service, then `{"type":"where","query":{"$or":[{"$eq":["level","error"]},{"$eq":["level","fatal"]}]}}`.

## Gotchas

- Timestamps are nanoseconds (traces use seconds).
- Field names are case-sensitive; discover them via the labels endpoint.
- Empty result: check field names, time range, data retention, pipeline JSON.
- Pipeline errors: each operator needs exactly 2 array elements; stage `type` must be `filter`, `where`, or `parse`.
- Errors look like `{"error":{"code":"...","message":"..."}}`. 400 bad query, 401 expired token, 403 insufficient permissions.
