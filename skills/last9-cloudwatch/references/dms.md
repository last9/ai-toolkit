# DMS

Use the shared scope, statistic, and evidence rules in [SKILL.md](../SKILL.md).

## Task and replication instance are separate scopes

Discover `ReplicationTaskIdentifier` and `ReplicationInstanceIdentifier` for task metrics. Host storage, memory, and network metrics can use the replication instance without a task dimension. Keep the actual account/region/instance scope on host queries; omitting an inapplicable task label does not authorize a fleet-wide query. Serverless replication has its own applicable metric and dimension set.

## Interpret replication latency before diagnosing

`CDCLatencySource` and `CDCLatencyTarget` are seconds. Target latency includes source capture delay as well as downstream processing; a high target value alone does not prove the target endpoint is the bottleneck. Retrieve both metrics for the same task, periods, and statistic. Compare their levels/trends and report what is observed before attributing a cause. Full-load metrics describe the initial load, while CDC metrics describe ongoing replication; confirm task phase.

For a latest-period target/source latency request, batch the four summary companion reads and calculate each matched period mean independently. For a window mean, use total Sum / total SampleCount per metric with matching coverage. Do not add source and target latency or substitute their difference for a directly measured stage duration without a documented model.

Units vary within DMS: read/write latency is seconds, network throughput is bytes/sec, and CDC/full-load bandwidth is documented in KB/sec. `MemoryUsage` and `MemoryUsageBytes` are not the same unit. Task CPU percentages may exceed 100% when multiple cores are used; do not clamp them or apply an instance CPU interpretation automatically. Preserve the documented source unit unless a verified conversion is requested.

Sources: [DMS task and replication-instance monitoring](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Monitoring.html), [CDC latency interpretation](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Troubleshooting_Latency.html).
