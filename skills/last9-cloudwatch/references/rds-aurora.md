# RDS and Aurora

Use the shared scope, statistic, and evidence rules in [SKILL.md](../SKILL.md).

## CPU and read latency

Resolve account, region, and database dimensions. For Aurora, choose instance, cluster, or role: AWS publishes [different dimension combinations](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/dimensions.html), so selecting every row with a cluster name can overlap resources.

Discover CPUUtilization and ReadLatency families, batch their companion reads, and verify source, labels, timestamps, and units. For stream summaries, use the latest companion pair for requested period averages; use the weighted template only for a requested window average with verified coverage. Report each metric's aggregation level separately.

[RDS metrics](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/rds-metrics.html) define CPUUtilization in Percent and ReadLatency in seconds. Confirm ingestion mapping before converting latency to milliseconds by multiplying by 1,000. Enhanced Monitoring and similarly named exporters can differ in units/definitions. Period latency averages or percentiles cannot establish whole-window percentiles without distributions or equivalent raw observations.
