# DynamoDB

Use the shared scope, statistic, and evidence rules in [SKILL.md](../SKILL.md).

## Distinguish table, index, operation, and account

Discover `TableName`, `GlobalSecondaryIndexName`, and `Operation` on each requested metric. Table-only and GSI rows describe different resources; specify which resource or deliberate combination the request concerns. Account-level metrics must remain account-scoped rather than being filtered by an invented table dimension. Global table replication metrics can add regional dimensions.

## Capacity totals differ from averages

`ConsumedReadCapacityUnits` and `ConsumedWriteCapacityUnits` use Sum for total consumed capacity units in a period. A Sum/SampleCount average is a different quantity and does not answer a consumed-capacity total. With complete disjoint period reports, sum their Sums once; divide by elapsed seconds only when average consumed units per second is requested. Provisioned capacity is a configured capacity level, not another consumption event total. On-demand resources need not publish a provisioned-capacity series.

For example, after verifying the metric and table/index selector, retrieve the raw Sum series over the fixed window or execute:

```promql
sum(sum_over_time(<consumed-capacity-sum>{<verified-scope>}[<window>]))
```

Confirm full period coverage before reporting a window total. Do not divide by SampleCount, use `increase()` on period summaries, or add repeated chart rollups.

For verified Metric Streams lineage, AWS documents period-end stamps (see the timestamp rule in [SKILL.md](../SKILL.md)): complete disjoint observations stamped `start + P`, `start + 2P`, through `end` cover the period-aligned interval `(start, end]`, and a missing observation stamped exactly at `start` leaves the first period covered. Cite that documentation and the lineage evidence in the report. For exporters or unverified lineage, report the observed stamps and state that boundary alignment is assumed.

`SuccessfulRequestLatency` is milliseconds and operation-specific; it excludes unsuccessful requests, so it is not end-to-end latency for all attempts. Throttle events, throttled requests, conditional failures, and transaction conflicts count different things. Publication conditions vary by metric: verify the definition and data path before interpreting an empty event series as zero. Missing data alone is not proof of healthy service.

Sources: [DynamoDB metrics and dimensions](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/metrics-dimensions.html), [consumed read capacity](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/metrics-dimensions.html#ConsumedReadCapacityUnits).
