# KMS

Use the shared scope, statistic, freshness, and evidence rules in [SKILL.md](../SKILL.md).

## Discover the applicable metric and key identity

Do not assume one universal KMS metric or key dimension. `SuccessfulRequest` counts successful cryptographic operations and commonly uses `KeyArn` plus `Operation`; `ReEncrypt` uses source and destination key dimensions. Inspect the returned labels and operation definition before filtering. Do not treat every management API action as a SuccessfulRequest operation, or sum source/destination views without checking overlap.

For a requested operation total, use the verified CloudWatch Sum for each disjoint period and sum only the requested key/operation population. SampleCount is observations, not automatically successful requests. Quota headroom needs the applicable regional quota and operation grouping; one key's success count cannot establish all attempted traffic, throttling, or remaining quota.

## Imported key material expiration

`SecondsUntilKeyMaterialExpiration` is a seconds-remaining measurement for applicable expiring imported key material, with `KeyId` as its key dimension. AWS documents Minimum for this metric. It is not a Unix timestamp, key age, rotation age, or operation count. Select its observed Minimum statistic, preserving the original sample time and applicable key identity.

For an expiry-horizon request, return the remaining seconds at that observation. If a calendar expiry is requested, add the horizon to the verified source timestamp using an available reliable date tool and identify it as a calculation from that observation. Do not add it to the query evaluation time or label an old horizon current. No observation may mean the key/material is inapplicable, non-expiring, or unavailable in the selected scope; it does not prove no key or no KMS activity.

Read-only metric investigation does not authorize importing/deleting key material, changing expiration, disabling keys, or altering key policies.

Source: [KMS CloudWatch metrics and dimensions](https://docs.aws.amazon.com/kms/latest/developerguide/monitoring-cloudwatch.html).
