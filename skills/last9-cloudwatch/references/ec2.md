# EC2

Use the shared scope, statistic, and evidence rules in [SKILL.md](../SKILL.md).

## Identify instance and reporting period

For an instance request, discover and select its actual `InstanceId` dimension. AWS also supports aggregation dimensions such as `AutoScalingGroupName`, `ImageId`, and `InstanceType` for applicable metrics; do not assume all rows are per-instance or sum aggregate rows with their instances. Metric availability depends on instance type and monitoring configuration.

Basic monitoring commonly supplies five-minute periods; detailed monitoring supplies one-minute periods for supported metrics. Some metrics retain their own cadence. Inspect actual timestamps and definitions before assuming sixty-second coverage.

## Levels, bytes, and credits

- `CPUUtilization` is percent. A window mean from stream summaries needs matched Sum/SampleCount coverage.
- `NetworkIn` and `NetworkOut` are bytes over the period. For total bytes, add disjoint period Sums once. For average bytes/sec, divide a complete total by elapsed seconds; SampleCount is not a time denominator.
- `StatusCheckFailed*` are status flags. A Maximum of 1 supports an observed failed check, not a count of distinct failures. Do not add the combined flag to its component flags.
- `CPUCreditBalance` is a balance, while `CPUCreditUsage` describes credits spent. Keep the metric's unit and reporting period; applying counter functions to a balance is not usage. Credit metrics are instance-family dependent.

For a network-total request, read the exact instance's raw Sum reports at the requested bounds, verify that the completed periods cover the interval, then total them or use the shared period-Sum template. Report partial coverage when periods are missing or the window cuts a period.

Guest memory and filesystem usage generally require agent/custom telemetry, not standard `AWS/EC2` metrics. Preserve a valid CloudWatch-agent or OTel source separately; absence from the EC2 namespace does not establish that memory data is unavailable everywhere.

Sources: [EC2 metrics and dimensions](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/viewing_metrics_with_cloudwatch.html), [basic and detailed monitoring](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/manage-detailed-monitoring.html).
