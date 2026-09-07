---
name: last9-cloudwatch
description: Investigate AWS CloudWatch metrics in Last9 through read-only MCP queries. Use for CloudWatch metric discovery, RDS or Aurora resource metrics, CloudWatch statistics and units, or sparse S3 daily metrics ("CloudWatch in Last9", "RDS CPU", "Aurora latency", "S3 metric is empty").
compatibility: Requires the Last9 MCP server connected to the session
metadata:
  author: last9
---

# last9-cloudwatch — investigate CloudWatch metrics in Last9

**Operating principle: establish the resource and the published statistic before choosing the calculation.** CloudWatch metrics can describe AWS resources without an application service, environment label, or APM instrumentation. Start with the requested AWS population; do not require traces to query its infrastructure metrics.

## Prerequisites and scope

Use the authenticated [Last9 MCP server](https://github.com/last9/last9-mcp-server) and its advertised tool schemas. This workflow reads existing telemetry. Creating streams, changing AWS permissions, configuring collectors, generating Terraform, and building dashboards are separate tasks.

Confirm the connected organization and selected datasource from the conversation and available connection or datasource information. Call `list_datasources` when selection is not already established. Carry the selected datasource into every discovery and query call; a different default is not a reason to change the user's selection. If the connection cannot access the intended organization, report that boundary before querying another one.

Pin the AWS account, region, resource, and UTC start/end times. Resolve relative times against an available clock once and reuse those bounds for comparisons. Discover the actual dimension keys before inserting filters. Account or region may be established by a dedicated datasource or integration configuration instead of a series label; state that evidence. If scope remains ambiguous, surface the available choices and resolve it before combining measurements.

If the needed tools are unavailable, explain the missing connection or capability. Analyze supplied observations when sufficient, but identify proposed queries as unexecuted. Never present invented calls or results as evidence.

## Tool reference

Read the live descriptions first; these are the relevant parameter shapes, not a replacement for the installed schemas.

| Tool | Use | Parameters |
|---|---|---|
| `list_datasources` | Resolve the datasource | Use its advertised schema |
| `prometheus_label_values` | Discover metric names or dimension values | `label`, `match_query`, `datasource`, `start_time_iso`, `end_time_iso` |
| `prometheus_labels` | Discover label names for a selector | `match_query`, `datasource`, `start_time_iso`, `end_time_iso` |
| `prometheus_instant_query` | Evaluate an expression at a fixed time, or read a raw range selector | `query`, `datasource`, `time_iso` |
| `prometheus_range_query` | Inspect an expression over the requested interval | `query`, `datasource`, `start_time_iso`, `end_time_iso` |

Use `label: "__name__"` for metric-name discovery. These query tools do not expose a `step` parameter in this interface; do not invent one. Preserve the distinction between a raw range selector evaluated once and a chart expression evaluated repeatedly.

## Discover, verify, then calculate

1. **Find candidate names.** Search the selected datasource and time window for the requested AWS namespace or metric. The [CloudWatch integration guide](https://last9.io/docs/integrations/observability/aws-cloudwatch-metrics/) documents the `amazonaws_com_AWS` prefix for its stream path; use it as a discovery hint, not a universal name contract. Exporters and other ingestion paths can use different names. A missing result under one prefix is not proof that the resource has no metrics.
2. **Inspect dimensions and actual samples.** Discover label names and relevant values, then execute a narrow selector for the chosen account, region, and resource. A catalog entry proves discoverability, not current delivery. `prometheus_labels` may return a generic catalog even with `match_query`; if it does, state that limitation and inspect a bounded candidate metric query's actual returned label keys. Inspect returned series labels and raw timestamps before trusting a filter or interpreting emptiness. Do not add `service_name`, `env`, `namespace`, or a guessed AWS dimension simply because it appears on another metric.
3. **Identify lineage and one dimension level.** Distinguish CloudWatch Metric Streams, exporters, and trace-derived metrics using integration information and observed series. Preserve valid mixed configurations. Keep sources separate until their populations, periods, and definitions justify combining them; overlapping copies cannot be added. Similarly, choose instance, cluster, or role aggregation deliberately. Removing labels with `sum by (...)` after selecting overlapping rows does not remove double counting.
4. **Establish the measurement contract.** Record the AWS metric, unit, statistic, publication period, timestamp meaning, and coverage. Check whether a sample is a period summary, instantaneous gauge, or cumulative counter. Establish units from the AWS metric definition and the ingestion mapping; a unit label is not guaranteed, and magnitude alone is not evidence. Follow the current integration guide and verify additional statistics and the actual ingestion format when relevant; do not infer a permanent format-version requirement from an old example. If dimensions appear only as an opaque encoded value, report the observed shape and the missing resource-level selection capability; do not invent direct label keys or recreate the stream.
5. **Execute the required calculation.** Build queries from discovered names and verified selectors. Execute them with the pinned datasource and times, inspect results, and cross-check units and arithmetic. If the inputs cannot support the requested statistic, return it as unavailable and name the evidence needed next.

Keep query outcomes distinct: a successful empty result contains no matching observations, while an explicit numeric zero is a measurement. An invalid query, authentication failure, or timeout establishes neither. Correct invalid arguments or expressions using the actual schema and discovered names, then retry the scoped read; otherwise report the blocking error rather than treating it as absence.

Discovery example for an RDS investigation, after substituting the selected datasource and UTC bounds:

```json
{
  "label": "__name__",
  "match_query": "{__name__=~\"amazonaws_com_AWS_RDS_.+\"}",
  "datasource": "<selected-datasource>",
  "start_time_iso": "<start-utc>",
  "end_time_iso": "<end-utc>"
}
```

This is input to `prometheus_label_values`, not a query result. Narrow discovery further with already-verified resource filters. Use returned metric names in the subsequent label and sample reads.

## Statistics and calculation guardrails

[CloudWatch Metric Streams](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-Metric-Streams.html) carry period statistics including Sum and SampleCount; additional statistics can be configured. The [OpenTelemetry translation](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-metric-streams-formats-opentelemetry-translation.html) explains the summary mapping. Verify that mapping for the series being queried before applying these recipes.

| Observed measurement | Interpretation and calculation |
|---|---|
| Confirmed stream-summary `_sum` and `_count` companions | Period Sum and SampleCount. `_sum / _count` gives the period's sample average when labels, period, and population match and count is positive. `_count` counts observations; it is not automatically a request count. |
| Several confirmed, disjoint period summaries | A sample-weighted window average is total Sum divided by total SampleCount. Averaging the period averages is wrong when counts differ. Verify coverage and boundaries before claiming a whole-window result. |
| An AWS metric whose Sum counts events | Add disjoint period Sums for an event total; divide by covered elapsed seconds for average events/sec only with the required complete coverage. Establish this from the metric's definition, not its suffix. |
| A gauge such as storage size or resource utilization | Report the requested level or a clearly defined aggregate. Summing observations over time does not give total storage or total utilization. |
| A verified cumulative exporter counter | `rate()` or `increase()` may apply with suitable history and reset handling. Do not transfer that treatment to CloudWatch period-summary companions because their names end in `_sum` or `_count`. |
| Observed minimum, maximum, or percentile series | Select the actual statistic label, including `quantile` where present. A maximum of period p99s is the peak period p99; it cannot establish a whole-window p99. Do not run `histogram_quantile()` on already-quantiled values. |
| Instance rows plus cluster, role, or other rollup rows | Select a non-overlapping population at one intended dimension level. Never sum both an aggregate and its constituent resources. |

For a confirmed summary family, the following are **templates**. Replace metric names, selectors, and window with observed values before execution:

```promql
<sum-metric>{<verified-scope>} / <count-metric>{<verified-scope>}
```

```promql
sum(sum_over_time(<sum-metric>{<verified-scope>}[<window>]))
/
sum(sum_over_time(<count-metric>{<verified-scope>}[<window>]))
```

The first expression needs one-to-one matching companion labels. The second additionally needs matching populations and periods, positive total SampleCount, and raw samples representing disjoint reports. Do not add arbitrary label-dropping modifiers to make an unexplained mismatch disappear. Do not silently turn a zero or missing denominator into zero utilization or latency.

Inspect raw sample times, for example with `<metric>{<verified-scope>}[<window>]` through `prometheus_instant_query` at the fixed end time. Chart points may repeat or resample earlier observations; they are not automatically independent stream publications. Missing periods, duplicate delivery, late data, boundary misalignment, or unknown timestamp semantics limit a whole-window total or average. State the supported coverage rather than filling gaps with zero.

## Worked example: RDS or Aurora CPU and read latency

For “show CPU and read latency for this database over this interval”:

1. Resolve the chosen account, region, and database using actual dimensions. For Aurora, determine whether the request concerns an instance, the cluster, or a role. AWS publishes [different dimension combinations](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/dimensions.html); inspect the selected series instead of combining every row with the cluster's name.
2. Discover the CPUUtilization and ReadLatency families in that scope. Verify whether the returned metrics are stream-summary companions, exporter gauges, or a different source. Read a small raw window and inspect labels, timestamps, and units before building the final expression.
3. If the observed family uses period Sum/SampleCount, execute the companion ratio for the period averages. For a requested full-window average, execute the weighted template only after verifying its coverage conditions. Keep CPU and latency calculations separate, and report their actual aggregation level.
4. [RDS CloudWatch metrics](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/rds-metrics.html) define CPUUtilization as Percent and ReadLatency as seconds. Confirm the ingested unit mapping. Convert seconds to milliseconds with a factor of 1,000 only when that is the observed input unit. Enhanced Monitoring or exporter metrics with similar names can have different definitions or units.
5. Report the measured values with the exact executed selectors and interval, or say which result is unavailable. Without distributions or equivalent raw observations, period latency averages and percentiles do not establish a whole-window latency percentile.

## Sparse metrics: S3 daily storage

An empty recent lookup for BucketSizeBytes or NumberOfObjects does not establish zero, deletion, or a stopped stream. These are [daily S3 storage metrics](https://docs.aws.amazon.com/AmazonS3/latest/userguide/metrics-dimensions.html), distinct from request metrics. AWS documents a [daily period and Average statistic](https://docs.aws.amazon.com/AmazonS3/latest/userguide/cloudwatch-monitoring-accessing.html) for viewing them.

Discover the actual bucket and storage-type dimensions. Read bounded history spanning the daily cadence, such as the last three days, and inspect the timestamps of actual samples. Keep this diagnostic history separate from the interval the user asked about. Distinguish a numeric zero, a last known observation, and no observation in the requested interval. Do not claim that a `last_over_time()` result's evaluation timestamp is the original publication time; use raw sample timestamps to establish the age.

If expected history is also empty, verify the datasource, filters, source configuration, statistic, and publication cadence before attributing the gap to ingestion. Use available read-only delivery evidence when present. If it is absent, report that whether delivery stopped remains unconfirmed. Do not infer an exact next publication time from “daily.”

## Metric availability and Discover visibility

A resource can have queryable CloudWatch metrics without appearing in a particular Discover view. Verify ingestion by executing a scoped metric query in the selected datasource. Investigate Discover identity and supported resource discovery separately, using the actual identity dimensions and current integration guidance. Missing application traces or a missing Discover row is not evidence that CloudWatch ingestion failed.

## Report the evidence

For each requested measurement, give the value and unit or **unavailable**, the AWS resource and dimension level, datasource and UTC interval, selected source/statistic, and the exact executed query with its returned evidence or tool-call reference. Separate observations from explanations and unresolved causes. Report partial coverage, last-known sample times, and any unsupported requested statistic explicitly; check that the prose arithmetic agrees with the samples and the stated result.

For an ingestion-versus-UI question, state what the metric query established and what remains unknown about discovery. Link the [Last9 metric explorer](https://app.last9.io/metrics) when useful.

## Related skills

Use `last9-logs` for a separate log investigation or `last9-traces` for application span analysis when relevant and available. Neither is a prerequisite for this CloudWatch workflow.
