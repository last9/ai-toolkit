---
name: last9-cloudwatch
description: Investigate AWS CloudWatch metrics in Last9 with read-only MCP queries. Covers Billing, RDS/Aurora, ElastiCache, MSK, DynamoDB, EC2, SQS, DMS, KMS, and S3. Discover resource metrics, interpret statistics and units, and distinguish sparse data from missing delivery.
compatibility: Requires the Last9 MCP server connected to the session
metadata:
  author: last9
---

# last9-cloudwatch

**Establish resource and statistic before calculating.** CloudWatch needs no application service, environment label, or APM instrumentation.

## Prerequisites and scope

Use the authenticated [Last9 MCP server](https://github.com/last9/last9-mcp-server) for read-only queries. AWS/collector changes, Terraform, and dashboards are separate tasks.

Establish the connected organization, selected datasource, AWS account, region, resource, and UTC bounds. Use `list_datasources` if unresolved; carry the selection into every call regardless of defaults. Resolve relative times once with an available clock. Datasource/integration configuration can establish account/region without labels; cite that evidence. Resolve ambiguous scope before combining data; never substitute an accessible organization for the intended one.

If tools are missing, use sufficient supplied observations or report the capability gap. Mark unexecuted queries; never invent results.

## Choose the AWS family

Before family-specific discovery or queries, read the matching reference. For a task spanning multiple families, load only those matching references. Namespace names below are discovery hints, not guaranteed ingested names or label spellings. Use the shared rules below for every source.

| Family | Namespace hint | Read when investigating |
|---|---|---|
| [Billing](references/billing.md) | `AWS/Billing` or a verified cost exporter | Estimated charges, currency, service and linked-account cost scope |
| [RDS / Aurora](references/rds-aurora.md) | `AWS/RDS` | Instance versus cluster/role metrics, CPU, latency, replication |
| [ElastiCache](references/elasticache.md) | `AWS/ElastiCache` | Cache node identity, engine versus host CPU, hits, evictions, lag |
| [MSK](references/msk.md) | `AWS/Kafka` | Broker versus topic/consumer-group metrics, throughput, consumer lag |
| [DynamoDB](references/dynamodb.md) | `AWS/DynamoDB` | Table/index/account scope, consumed capacity, throttling, latency |
| [EC2](references/ec2.md) | `AWS/EC2` | Instance CPU, period network bytes, status checks, credit balances |
| [SQS](references/sqs.md) | `AWS/SQS` | Approximate backlog and age, message-operation counts, inactive queues |
| [DMS](references/dms.md) | `AWS/DMS` | Replication task versus instance, source/target CDC latency |
| [KMS](references/kms.md) | `AWS/KMS` | Operation counts, key material expiration, metric applicability |
| [S3](references/s3.md) | `AWS/S3` | Daily storage versus request metrics, last-known versus current |

## Tool reference

Installed schemas take precedence over this reference:

| Tool | Relevant parameters |
|---|---|
| `list_datasources` | Advertised schema |
| `prometheus_label_values` | `label`, `match_query`, `datasource`, `start_time_iso`, `end_time_iso` |
| `prometheus_labels` | `match_query`, `datasource`, `start_time_iso`, `end_time_iso` |
| `prometheus_instant_query` | `query`, `datasource`, `time_iso` |
| `prometheus_range_query` | `query`, `datasource`, `start_time_iso`, `end_time_iso` |

Discover names with `label: "__name__"`. Do not invent a `step` parameter. Distinguish raw range selectors evaluated once from repeatedly evaluated charts.

## Discover and execute efficiently

1. **Find names and inspect samples.** The [integration guide](https://last9.io/docs/integrations/observability/aws-cloudwatch-metrics/) documents `amazonaws_com_AWS` for its stream path. Treat it as a discovery hint: exporters can use other names. Missing one prefix does not prove missing resource metrics. Discover dimensions, then execute a bounded selector. Catalog membership proves discoverability, not delivery. `prometheus_labels` may return generic keys even with `match_query`; state that limitation and use actual returned series labels. Do not invent `service_name`, `env`, `namespace`, or AWS dimensions from another metric's catalog.
2. **Verify lineage and population.** Distinguish Metric Streams, exporters, and traces using integration information and observed series. Preserve valid mixed sources; combine only when definitions, periods, and populations justify it. Choose instance, cluster, or role scope deliberately. Removing labels after selecting overlapping copies or rollups does not remove double counting.
3. **Establish semantics.** Identify the metric, unit, statistic, period, timestamp meaning, and coverage; distinguish period summaries, gauges, and cumulative counters. Treat sample timestamps as observation timestamps. In both documented Metric Streams OpenTelemetry formats ([0.7.0](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-metric-streams-formats-opentelemetry-translation.html) and [1.0.0](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-metric-streams-formats-opentelemetry-100.html)) the Summary datapoint's `time_unix_nano` is the CloudWatch period `endTime`, so a verified stream sample is stamped at period end. Cite that source together with the verified stream lineage when a coverage claim depends on it; for exporters or unverified lineage the mapping is unknown, so label period-boundary claims as assumptions. Use AWS definitions and ingestion mapping for units, not magnitude or an assumed unit label. Check the current guide and observed format/additional statistics rather than imposing a historical format version. If dimensions are opaque encoded values, report the resource-selection limitation; do not invent direct keys or recreate the stream.
4. **Batch independent reads and reuse evidence.** Once scopes are known, batch companion Sum/Count reads and independent discovery across requested metrics. Reuse verified names, labels, raw samples, and calculations at the same scope/time. Skip redundant catalog lookups and extra calculations: a latest-period request does not need a separate weighted window average. Execute the required expression or derive the requested result from returned raw operands, check arithmetic and units, then report as soon as the requested measurements are supported. If support is unavailable, report the gap and needed evidence instead of expanding the investigation.

`prometheus_label_values` example: substitute datasource/UTC bounds and add verified resource filters.

```json
{
  "label": "__name__",
  "match_query": "{__name__=~\"amazonaws_com_AWS_RDS_.+\"}",
  "datasource": "<selected-datasource>",
  "start_time_iso": "<start-utc>",
  "end_time_iso": "<end-utc>"
}
```

## Query outcomes and statistics

A successful empty expression returned no values; an explicit numeric zero is a measurement. Describe an empty result as no matching samples returned for that selector and window. Do not call it not ingested, not delivered, not reported, or a data gap: those are causes that need separate evidence such as widened history, other statistics, or datasource configuration. An empty ratio does **not** prove missing raw observations. Inspect each raw operand at the same verified scope/window for absent samples, zero or invalid denominators, and vector-matching differences. Invalid queries, authentication failures, and timeouts establish neither zero nor absence. Repair invalid arguments/expressions using the actual schema and discovered names, retry the scoped read, or report the blocking error.

[Metric Streams](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-Metric-Streams.html) carry period Sum and SampleCount plus configurable statistics. Verify the series' [summary mapping](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-metric-streams-formats-opentelemetry-translation.html) before using these recipes:

| Observed measurement | Calculation and guardrail |
|---|---|
| Confirmed `_sum` / `_count` companions | Period Sum / SampleCount is the sample average when labels, period, and population match and count is positive. SampleCount counts observations, not automatically requests. |
| Disjoint period summaries | Window average = total Sum / total SampleCount. Averaging period averages is wrong when counts differ. Whole-window claims require matching coverage and boundaries. |
| Metric whose Sum counts events | Add disjoint period Sums; divide by elapsed seconds for average events/sec only with complete coverage. Establish event semantics from the metric definition, not its suffix. |
| Gauge: storage or utilization | Report the requested level or defined aggregate. Adding observations over time is not total storage or utilization. |
| Verified cumulative exporter counter | `rate()` / `increase()` may apply with sufficient history and reset handling. Never apply them to period summaries merely because of `_sum` / `_count` suffixes. |
| Minimum, maximum, percentile | Select the actual statistic label (`quantile` if present). In the documented [OpenTelemetry stream translation](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-metric-streams-formats-opentelemetry-translation.html), summary `quantile` 0 carries the period Minimum and `quantile` 1 the period Maximum; confirm the ingested format before relying on that mapping, because other formats and exporters expose Min/Max differently. A period Maximum is the largest value observed in that period, not the latest reading. Maximum period p99 is peak period p99, not whole-window p99. Do not apply `histogram_quantile()` to already-quantiled values. |
| Instance, cluster, role, or other rollups | Select one non-overlapping population; never add an aggregate and its constituents. |

For verified summaries, substitute observed names, selectors, and window:

```promql
<sum-metric>{<verified-scope>} / <count-metric>{<verified-scope>}
```

```promql
sum(sum_over_time(<sum-metric>{<verified-scope>}[<window>]))
/
sum(sum_over_time(<count-metric>{<verified-scope>}[<window>]))
```

The period ratio needs one-to-one companion matching. The window ratio additionally needs disjoint reports, matching populations/periods, and positive total SampleCount. Do not hide unexplained mismatches by dropping labels or convert a missing/zero denominator into zero latency or utilization.

Inspect raw times using `<metric>{<verified-scope>}[<window>]` through `prometheus_instant_query` at the fixed end. Use verified raw-selector bounds and sample timestamps for window membership; do not contradict them with unverified UTC conversions. Membership alone does not establish complete period coverage. Check result type and timestamp meaning: source observation times need original samples. Vector tuples and chart points can carry evaluation times or repeat earlier observations. Missing periods, duplicates, late data, misaligned boundaries, or unknown timestamp semantics limit totals/averages; report supported coverage instead of filling gaps with zero.

Keep **last-known** and **current** separate. A historical query interval is not a freshness requirement unless the user explicitly makes it one. Honor a user-specified freshness window; otherwise probe each raw companion at the requested end time, separately from widened history. Do not invent a production freshness threshold. Widened history or a historical `last_over_time()` result cannot establish currentness; its evaluation time is not source publication time. If the observations do not establish currentness, report current **unavailable** and the last-known value separately.

Preserve exact returned Unix seconds. Verify UTC conversion and any age calculation with a reliable available tool; otherwise report the epoch only and omit converted dates/times and computed ages. `vector(epoch)` merely echoes a number, not a verified time conversion. Never round a source timestamp to a date or midnight.

## Report evidence and separate Discover identity

Keep requested output names. Give value/unit or **unavailable**, resource/dimension level, datasource/UTC interval, source/statistic, and executed queries with evidence/call references. Cite every operand actually used, including Sum and SampleCount for an average. State partial coverage, last-known times, unsupported statistics, and unresolved causes; check prose arithmetic against the samples and result.

A resource may have queryable metrics without a Discover row. Establish availability with a scoped metric query; investigate Discover identity and supported resource profiles separately using actual dimensions and current guidance. Missing traces or a Discover row does not prove ingestion failure. Link the [metric explorer](https://app.last9.io/metrics) when useful.

## Related skills

Use available `last9-logs` or `last9-traces` for separate log/span tasks; neither is required.
