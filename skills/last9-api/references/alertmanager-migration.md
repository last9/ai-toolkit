# Alertmanager migration

Source: Last9 "Prometheus alertmanager Migrations" documentation.

Converts a Prometheus Alertmanager-compatible alert rules YAML into Last9 alert configuration.

```text
POST /entities/migrate/alertmanager     (org base)
```

- Request body: the Alertmanager YAML, sent as-is.
- Response: YAML compatible with Last9.

## Recipe

```bash
python3 <skill-dir>/scripts/last9.py api POST entities/migrate/alertmanager \
  -d @sample.yaml -H 'Content-Type: application/yaml' > last9-alerts.yaml
```

`-d` sets `Content-Type: application/json` by default; the doc's curl uses `--data-binary` with no content type, so override it with `-H` if the server rejects the default. This is unverified.

## Response shape (trimmed)

```yaml
entities:
  - name: payment service
    type: alert-manager
    external_ref: payment service-alert-manager-alert-manager
    entity_class: alert-manager
    indicators:
      - name: "EXPR: HighRequestLatency - breach"
        query: job:request_latency_seconds:mean5m{service="payment"} > 0.5
    alert_rules:
      - name: High request latency
        indicator: "EXPR: HighRequestLatency - breach"
        total_minutes: 10
        bad_minutes: 10
        greater_than: 0
```

Each Alertmanager rule yields an indicator plus an alert rule keyed to it.

## Notes

- The doc writes the path as `/v4/organizations/{org_slug}/entities/migrate/alertmanager` on `app.last9.io` (no `/api` prefix, unlike every other endpoint). The recipe uses the org-relative form like the other references; this is unverified.
- Review the converted YAML before applying it; the doc does not describe how unsupported rule features are handled.
