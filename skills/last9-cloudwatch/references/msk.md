# Amazon MSK

Use the shared scope, statistic, and evidence rules in [SKILL.md](../SKILL.md).

## Scope follows the metric

Discover cluster, broker, topic, and consumer-group dimensions for each metric. AWS dimension names such as `Cluster Name`, `Broker ID`, and `Consumer Group` may be normalized by ingestion; use actual returned keys. A broker filter applied to a consumer-group series can silently remove the requested population.

Broker metrics, cluster aggregates, and topic breakdowns are not interchangeable. `UnderReplicatedPartitions` has a broker scope; do not classify every health metric as cluster-only. Monitoring level, broker type, cluster mode, and consumer state can affect metric availability. Confirm applicability before treating an absent metric as healthy or an ingestion fault.

## Throughput and lag

- `BytesInPerSec`, `BytesOutPerSec`, and `MessagesInPerSec` already describe rates, so applying `rate()` again changes the quantity. Match the average to the requested window: for the latest period use that matched Sum/SampleCount pair; for a mean over the requested interval use total Sum / total SampleCount across the disjoint periods, read from the raw companion series over that window rather than a single instant query returning only the last period. Combining broker/topic rows needs a verified non-overlapping population.
- `MaxOffsetLag` is the maximum offset lag across the applicable partitions; `SumOffsetLag` is a different aggregate. Neither is a count of unique messages processed during the observation window.
- `EstimatedMaxTimeLag` is in seconds. An offset count cannot be converted to time without additional evidence.

For a requested worst consumer lag, select the exact cluster, consumer group, and topic. Retrieve the observed Maximum statistic (for a verified summary mapping, the actual maximum quantile) and take the maximum over the requested window. Report it as peak observed maximum offset lag, with partition aggregation and sample coverage. Do not sum per-period maxima or substitute SumOffsetLag. If only average observations exist, say the requested peak is unavailable.

Sources: [MSK metrics and dimensions](https://docs.aws.amazon.com/msk/latest/developerguide/metrics-details.html), [consumer lag monitoring](https://docs.aws.amazon.com/msk/latest/developerguide/consumer-lag.html).
