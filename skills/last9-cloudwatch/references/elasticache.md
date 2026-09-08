# ElastiCache

Use the shared scope, statistic, and evidence rules in [SKILL.md](../SKILL.md).

## Select engine and entity level

Establish Valkey, Redis OSS, or Memcached and node-based versus serverless deployment before choosing metrics. Node-based metrics commonly use `CacheClusterId` and `CacheNodeId`; discover their actual ingested keys and combinations. Do not equate a replication group with a cache cluster or add node rows to a cluster aggregate. Serverless and Memcached have different metric inventories; absent Valkey/Redis metrics do not prove a broken stream.

## Interpret the measurement

- `EngineCPUUtilization` measures engine CPU; `CPUUtilization` measures the host. Both are percentages with different denominators, so they are not interchangeable or additive.
- `BytesUsedForCache` and `FreeableMemory` are byte levels; `CurrConnections` is a connection level. `Evictions`, `Reclaimed`, `CacheHits`, and `CacheMisses` describe distinct events. Use verified period Sums for event totals, not SampleCount or a peak statistic.
- `CacheHitRate` is a percentage. Do not average node percentages into a fleet hit ratio without request weights; matched hit/miss totals can support the ratio when their populations and periods agree.
- `ReplicationLag` is documented in seconds. `SuccessfulReadRequestLatency`, `SuccessfulWriteRequestLatency`, and command-family latency such as `GetTypeCmdsLatency` are microseconds. `DurabilityLag` and `DB0AverageTTL` are milliseconds. Check the exact metric/engine definition before converting; display requirements do not change source units.
- `GetTypeCmds` and `GetTypeCmdsLatency` cover read-only commands across data types; AWS examples include `GET`, `HGET`, `SCARD`, and `LRANGE`. Command groups overlap: `LRANGE` also belongs to `ListBasedCmds`. Do not add these groups as disjoint populations or infer command exclusions from a metric name.

## Answer an engine CPU or latency request

Discover the requested node's family and read both summary companions independently at the fixed scope/time. A mean of engine command-latency observations is not automatically request-weighted or end-to-end client latency. For the latest period, use that matched pair. For a window average, use total Sum / total SampleCount with complete matching coverage. Report engine CPU and host CPU separately if both were requested. Keep primary/replica identity for replication metrics; do not turn an absent replica-only metric into zero lag.

Sources: [Valkey and Redis OSS metrics](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/CacheMetrics.Redis.html), [Memcached metrics](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/CacheMetrics.Memcached.html), [node dimensions](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/CloudWatchMetrics.html), [serverless metrics](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/serverless-metrics-events-redis.html).
