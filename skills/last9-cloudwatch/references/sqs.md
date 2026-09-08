# SQS

Use the shared scope, statistic, freshness, and evidence rules in [SKILL.md](../SKILL.md).

## Queue identity and approximate measurements

Discover `QueueName` and retain account/region; names need not be globally unique. Establish standard, FIFO, and fair-queue applicability before selecting feature-specific metrics. Quiet-group and noisy-group metrics concern fair queues, not a universal FIFO-only inventory.

`ApproximateNumberOfMessagesVisible` is waiting backlog, `ApproximateNumberOfMessagesNotVisible` is in-flight messages, and `ApproximateNumberOfMessagesDelayed` is delayed messages. They are approximate levels, not cumulative counters. `ApproximateAgeOfOldestMessage` is seconds; its treatment of repeatedly received or moved messages can affect its meaning. A DLQ age is not automatically total time since original enqueue.

## Choose the requested statistic

For the latest period's Maximum, use the most recent source observation of the verified Maximum statistic and report its timestamp. A maximum over the whole requested interval answers the window peak; it can differ from the latest period's Maximum.

For peak oldest-message age, select the exact queue and observed Maximum statistic, then take its maximum over the requested interval. If the stream mapping exposes maxima through a quantile, discover that label/value before using `max_over_time()`. Sum/SampleCount answers an average, not peak age. Adding age or backlog observations across time does not produce unique messages or message delay.

`NumberOfMessagesSent`, `NumberOfMessagesReceived`, and `NumberOfMessagesDeleted` count messages sent, received, or deleted with different semantics. Receives and deletes can include repeated processing; they are not interchangeable with unique messages or exact successfully completed work. Use disjoint period Sums for the requested message total and cite its definition. `NumberOfEmptyReceives` counts receive calls with no returned messages; it is not queue depth.

Inactive queues can stop emitting metrics and resume with delay. An empty recent query does not prove the queue was deleted, had zero backlog, or stopped delivering telemetry. Separate a last-known observation from current data using the shared freshness rules.

Sources: [SQS metrics and semantics](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-available-cloudwatch-metrics.html), [CloudWatch monitoring and inactive queues](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/monitoring-using-cloudwatch.html).
