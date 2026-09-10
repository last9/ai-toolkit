# Billing

Use the shared scope, statistic, freshness, and evidence rules in [SKILL.md](../SKILL.md).

## Establish the cost source

`AWS/Billing` `EstimatedCharges` is an estimated accumulated charge for the current month, not a daily increment, finalized invoice, or amortized cost. AWS publishes billing metrics in US East (N. Virginia), covering worldwide charges, and currently supports USD. Account/resource region and billing-metric region therefore need not be the same.

Discover the actual `Currency`, `ServiceName`, and `LinkedAccount` dimensions where available. Select total account charges, a service, or a linked-account/service combination deliberately. Do not add a total row to its service or account breakdowns, mix currencies, or infer linked-account coverage from an accessible total.

Cost exporters can expose names such as `aws_cost_*` with amortized, unblended, or other definitions. These are a separate lineage: inspect their reporting period, currency, scope, and accounting definition. Do not map an exporter gauge to `EstimatedCharges` solely because both are monetary, or describe their difference as a verified discount without accounting evidence.

## Answer an estimated-charge request

Discover the requested cost family and scope, then retrieve the latest original observation within an appropriate bounded history. For verified stream summaries, use matching Sum/SampleCount for a period average only when that is the represented statistic; otherwise select the observed AWS statistic. A statistic label such as `quantile` identifies a period statistic (Minimum, Maximum), never the latest reading; the latest estimate is the most recent observation of the selected statistic. Report the latest estimate with currency, month/period, and original timestamp. Do not sum repeated month-to-date readings or use `rate()` / `increase()` on a charge gauge. A difference between readings is only a change in the estimate unless adjustments and period boundaries are understood.

Billing updates are sparse. A widened historical result supports a last-known estimate, not currentness; follow the shared current probe and user freshness rules. Missing billing data can reflect configuration or scope, and does not prove zero spend or stopped delivery. Do not change billing preferences as part of this investigation.

Source: [CloudWatch billing metrics and estimated charges](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/monitor_estimated_charges_with_cloudwatch.html).
