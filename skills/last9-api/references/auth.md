# Authentication

Source: Last9 "Getting started with API" documentation.

## Roles

- Admins can generate and revoke refresh tokens, and exchange them for access tokens.
- Editors can exchange existing refresh tokens for access tokens but cannot generate refresh tokens. They must ask an Admin.
- Viewers cannot access the API Access page.

Tokens are managed at https://app.last9.io/settings/api-access. The Refresh Token tab is Admin-only. Refresh tokens are shown only once at creation.

## Token model

- A refresh token is created by an Admin with a name and a scope: read, write, or delete.
- Exchange it for a short-lived access token. Access tokens expire after 24 hours.
- Scopes: read tokens only read state; write tokens create or modify data; delete tokens can remove data irrevocably, so use them sparingly.
- Revoking a refresh token invalidates it immediately, and access tokens generated from it are rejected.
- Token creation and revocation appear in Settings > Audit Trail.

## Observed behavior (verified live)

- Access token lifetime was observed at 72h although the docs say 24h. The CLI uses `expires_at`, so never hardcode a lifetime.
- Refresh tokens are not rotated on exchange: the response returns the same refresh token.
- A malformed or garbage access token returns HTTP 400 with `invalid refresh token: ...`. The wording is misleading; it means the access token is bad.

## Base URL

```text
https://{domain}/api/{version}/organizations/{org}/{endpoint}
```

`last9.py` derives the host and `{org}` from the refresh token's claims, so you rarely type either.

## Exchange endpoint

```text
POST https://app.last9.io/api/v4/oauth/access_token
```

The OAuth endpoint does not include the organization in the URL. Body:

```json
{ "refresh_token": "<refresh-token>" }
```

Response (trimmed):

```json
{
  "access_token": "<access-token>",
  "expires_at": 1587412870,
  "issued_at": 1587240070,
  "refresh_token": "<refresh-token>",
  "type": "Bearer",
  "scopes": ["read", "write", "delete"]
}
```

`last9.py` does this for you and caches the result. It keeps your original refresh token and does not store the one returned.

## Header rules

The token goes in `X-LAST9-API-TOKEN`, prefixed with `Bearer ` (with a trailing space).

| Example | Result |
| ------- | ------ |
| `X-LAST9-API-TOKEN: Bearer <access-token>` | correct |
| `X-LAST9-API-TOKEN: <access-token>` | 400 `{"error":"invalid access token"}` (missing Bearer prefix) |
| `Authorization: Bearer <access-token>` | 401 (wrong header) |

An expired access token returns `{"error": "Authorization token is expired"}`.

## Recipes

Check identity (no secrets printed):

```bash
python3 <skill-dir>/scripts/last9.py status
```

Second org or a write-scoped token under its own profile:

```bash
! python3 <skill-dir>/scripts/last9.py --profile writer login
python3 <skill-dir>/scripts/last9.py --profile writer status
```

CI: export `LAST9_REFRESH_TOKEN` from a secret, then call `api` as usual.

Raw curl, for environments without Python only (placeholders, not real values):

```bash
ACCESS=$(curl -s -X POST https://app.last9.io/api/v4/oauth/access_token \
  -H 'Content-Type: application/json' \
  -d '{"refresh_token":"<refresh-token>"}' | python3 -c 'import sys,json;print(json.load(sys.stdin)["access_token"])')
curl -H "X-LAST9-API-TOKEN: Bearer $ACCESS" \
  'https://app.last9.io/api/v4/organizations/<org>/logs/api/v1/labels?start=<ns>&end=<ns>'
```
