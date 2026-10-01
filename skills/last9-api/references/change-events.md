# Change events

Source: Last9 "Change Events" and GitHub Actions integration documentation. Needs a **write**-scope token (use a dedicated profile).

## Send an event

```text
PUT /change_events        (org base)
```

| Field | Required | Description |
| ----- | -------- | ----------- |
| `event_name` | yes | Event identifier; becomes a label on the metric |
| `timestamp` | no | ISO8601; defaults to now |
| `event_state` | no | `start` or `stop`; defaults to `start` |
| `attributes` | no | Key-value pairs; become labels |
| `value` | no | Sample value; defaults to `1` for start, `2` for stop |
| `data_source_name` | no | Cluster to store events in; defaults to the cluster designated for change events |

Success: HTTP 200, `{"message":"success"}`.

Last9 converts each event into the metric `last9_change_events`. Only `attributes` become labels; the API adds `event_name` and `event_state` itself.

## Attributes that matter

- Set `service_name` to your APM service name **exactly** (case included) or no chart markers appear. Events are still stored and queryable. `service` is accepted as an alias.
- Set the environment with `deployment_environment` or `env` (first non-empty, in that order). Discover scopes markers by it.
- Store events in the same cluster as the metrics you want to correlate with.
- `event_name` also colours the marker by substring (case-insensitive, first match wins): feature flag (`flag`, `launchdarkly`, `toggle`, `experiment`), deploy (`deploy`, `release`, `rollout`, `rollback`, `build`, `version`), infrastructure (`scal`, `restart`, `reboot`, `config`, `terraform`, `migration`, `maintenance`, `infra`, `node`, `cluster`), otherwise neutral.
- Naming examples: `deployment_start` / `deployment_complete`, `config_update_redis`, `feature_flag_toggle`, `db_migration_start` / `db_migration_complete`.

## Recipes

Deploy start and stop from CI:

```bash
L9="python3 <skill-dir>/scripts/last9.py --profile writer api"
$L9 PUT change_events -d "{\"event_name\":\"deployment\",\"event_state\":\"start\",\"attributes\":{\"service_name\":\"$SERVICE_NAME\",\"deployment_environment\":\"$DEPLOY_ENV\",\"version\":\"$GIT_SHA\",\"team\":\"$TEAM\"}}"
# ... deploy ...
$L9 PUT change_events -d "{\"event_name\":\"deployment\",\"event_state\":\"stop\",\"attributes\":{\"service_name\":\"$SERVICE_NAME\",\"deployment_environment\":\"$DEPLOY_ENV\",\"version\":\"$GIT_SHA\"}}"
```

For a payload file: `... api PUT change_events -d @event.json`.

Verify in PromQL (Metrics Explorer): `last9_change_events{event_name="deployment", deployment_environment="production"}`.

GitHub Actions: the documented Last9 Deployment Marker action sends events without custom steps. Its inputs include `env` (required; must match APM `deployment_environment`), `service_name` (defaults to repo name), `event_state` (`start`, `stop`, or `both`; default `stop`), `event_name` (default `deployment`), `custom_attributes` (JSON string).

## Gotchas

- Each call writes exactly one sample; there is no periodic refresh. For "stuck in a state" alerts, push the `start` event once in real time (re-pushing resets elapsed time) and size the PromQL lookback larger than the longest stuck time you want to catch (about 3-4x the threshold).
- Backdated timestamps past the database's backfill limit are rewritten to the ingestion time. Send events in real time.
- If a `stop` never arrives, such an alert keeps firing until one is pushed.
- Markers on dashboards need a **Label** variable targeting `service` or `service_name`; toggle shows 0 otherwise.
- Any valid ISO8601 timestamp is accepted (no 18-24h cap).
