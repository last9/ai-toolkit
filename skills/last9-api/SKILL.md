---
name: last9-api
description: Call the Last9 REST API from the command line with a stdlib Python helper that handles refresh-token exchange, access-token caching, and the X-LAST9-API-TOKEN header. Use when calling the Last9 REST API from scripts, CI, or an agent without the MCP server — exchanging refresh tokens for access tokens, sending change events, querying logs or traces over HTTP, migrating Alertmanager rules ("last9 api", "access token", "refresh token", "change events", "X-LAST9-API-TOKEN").
compatibility: Requires python3; network access to app.last9.io
metadata:
  author: last9
---

# Last9 REST API

`<skill-dir>/scripts/last9.py` is a single-file, stdlib-only Python 3.8+ CLI. It stores the refresh token, exchanges it for short-lived access tokens (docs say 24h; 72h observed, see references/auth.md), caches them, sets the auth header, and retries once if a token has expired.

## REST vs MCP

- If Last9 MCP tools are connected, prefer them for interactive investigation. See the `last9-logs` and `last9-traces` skills.
- Use this skill for automation, CI, change events, Alertmanager migration, or any session without the MCP server.

## Setup

The user runs login themselves. Never ask the user to paste a token into chat.

1. Check first: `python3 <skill-dir>/scripts/last9.py status`. Exit 0 means already logged in.
2. If not logged in, tell the user to run this in their own session (the `!` prefix runs it there):

   ```text
   ! python3 <skill-dir>/scripts/last9.py login --region <region>
   ```

   It opens the API Access page, prompts for the refresh token with hidden input, validates it by exchanging it, and saves it to `~/.last9/credentials` (mode 0600). Only Admins can create refresh tokens; Editors must ask an Admin. `--region` is saved with the profile and added automatically to logs/traces calls. Add `--no-browser` to skip opening the browser.
3. In CI, set `LAST9_REFRESH_TOKEN` from a secret store instead. It wins over saved profiles and is never written to disk.
4. Run `status` again to confirm org, host, scopes, and expiry. It prints no secrets.

**Finding your region:** use the region the org's data lives in (for example `ap-south-1`). If unsure, check the Last9 UI or org settings, or ask the user. Never guess in a loop. `LAST9_REGION` overrides the saved region.

Config lives in `~/.last9` (override with `LAST9_CONFIG_DIR`). `logout` removes a profile.

## Hard rules

- Always call the API through `last9.py api`. It sets `X-LAST9-API-TOKEN: Bearer <token>` and refreshes expired tokens. Do not hand-build the header.
- Never print, echo, or log a token or the refresh token into the transcript. Use `last9.py token` only when piping into another tool (`$(...)`).
- Pick the profile by scope and org: `--profile <name>` (or `LAST9_PROFILE`). Keep a read-only profile for queries and a separate write profile for change events or migrations. One profile per org.
- `api` refuses full URLs whose host differs from the token's host.
- When comparing query results, pin absolute `start`/`end` values. Two "last N minutes" queries issued seconds apart already diverge.

## Using `api`

```bash
python3 <skill-dir>/scripts/last9.py api METHOD PATH [-d DATA] [-q k=v ...] [-H 'K: V' ...] [-i]
```

- `PATH` without a leading `/api/` is relative to `https://<host>/api/v4/organizations/<org>/`. A path starting `/api/` is used on the token's host (for example `/api/v4/oauth/...`).
- `-q k=v` is repeatable and URL-encoded. `-d` takes a literal string, `@file`, or `-` for stdin and sets `Content-Type: application/json`.
- 2xx: body to stdout, exit 0. Otherwise: body to stdout, `HTTP <code>` to stderr, exit 1. `-i` prints the status on success too.

## Task to reference

| Task | Reference |
| ---- | --------- |
| Roles, scopes, token expiry, revocation, header rules, raw curl | [references/auth.md](references/auth.md) |
| Query, filter, and discover labels in logs | [references/logs.md](references/logs.md) |
| Query traces, search by duration, fetch a trace, tags | [references/traces.md](references/traces.md) |
| Send deploy/config change events from CI or scripts | [references/change-events.md](references/change-events.md) |
| Convert Prometheus Alertmanager rules to Last9 config | [references/alertmanager-migration.md](references/alertmanager-migration.md) |

## Errors

| Symptom | Meaning | Fix |
| ------- | ------- | --- |
| `400 {"error":"invalid access token"}` | Header value missing the `Bearer ` prefix | Use `last9.py api`; never send the raw token |
| `401` on an API call | Wrong header name (`Authorization`), or invalid or expired token | `api` retries once with a fresh token. If it still fails, run `status` and re-login |
| `{"error":"Authorization token is expired"}` | Access token past its `expires_at` | Handled automatically by `api` (forced refresh and one retry) |
| "refresh token invalid, expired, or revoked" | Exchange returned 400, 401, or 403 | The user generates a new refresh token at https://app.last9.io/settings/api-access and re-runs login |
| "not logged in" | No `LAST9_REFRESH_TOKEN` and no saved profile | Have the user run login (see Setup) |
| `400 region query parameter is required` | Logs/traces call without a region | Pass `-q region=<r>`, set `LAST9_REGION`, or `login --region <r>` |
| `500 ERR_S3_CONFIG_MISSING` or `502` "Maintenance Mode" HTML on logs/traces | Wrong region for this org | Use the org's real region; do not retry other regions blindly |
| `400 invalid refresh token: ...` from an API call | Misleading wording; the access token is bad | Delete `~/.last9/cache/<profile>.json` or re-login |
| `403` | Token scope too low for the operation | Use a profile whose refresh token has the needed scope (read, write, delete) |
| "refusing to send token to foreign host" | Full URL on a host other than the token's | Use a relative path |
