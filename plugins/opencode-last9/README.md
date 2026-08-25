# Last9 for OpenCode

[![npm version](https://img.shields.io/npm/v/@last9/opencode-plugin.svg)](https://www.npmjs.com/package/@last9/opencode-plugin)

Connect [OpenCode](https://opencode.ai) to your Last9 production telemetry — logs, metrics, traces, exceptions, database queries, alerts, and deployments — through the hosted [Last9 MCP server](https://last9.io/mcp/). Ships the Last9 investigation skills so your agent knows which query to write, not just how to write one.

## Install

Add the plugin to your `opencode.json` with your org slug (the part after `app.last9.io/` in your browser URL):

```json
{
  "$schema": "https://opencode.ai/config.json",
  "plugin": [["@last9/opencode-plugin", { "org": "<org-slug>" }]]
}
```

Restart OpenCode, then authenticate once:

```shell
opencode mcp auth last9
```

Your browser opens, you approve, done. Tokens are stored securely and refreshed automatically.

Prefer environment variables? Skip the options tuple:

```json
{ "plugin": ["@last9/opencode-plugin"] }
```

```shell
export LAST9_ORG_SLUG="<org-slug>"
```

## What it registers

- **`last9` MCP server** — a remote MCP endpoint at `https://app.last9.io/api/v4/organizations/<org-slug>/mcp`. OpenCode handles OAuth automatically (dynamic client registration + browser flow).
- **Last9 skills** — the canonical skills from [`last9/ai-toolkit`](https://github.com/last9/ai-toolkit) (`last9-logs`, `last9-traces`, `go-agent-install`, `sidekiq-debugging`), loaded via `skills.paths`.

## Configuration

| Option | Env fallback | Description |
|--------|--------------|-------------|
| `url` | `LAST9_MCP_URL` | Full MCP endpoint URL. Overrides `org`; use for self-hosted or preview environments. |
| `org` | `LAST9_ORG_SLUG` | Org slug; builds `<host>/api/v4/organizations/<org>/mcp`. |

Precedence: `url` option > `LAST9_MCP_URL` > `org` option > `LAST9_ORG_SLUG`. With nothing set, the plugin ships skills only and leaves MCP config untouched. A `last9` entry you define yourself in any config file always wins.

## Use it

Once authenticated, just ask:

```
Why did checkout-service latency spike in the last hour?
```

```
Find log errors from the payments deployment 30 minutes ago
```

The bundled skills steer the agent toward service-first scoping, attribute filters over body search, and aggregate-then-drill investigation.

## Verify

```shell
opencode mcp list   # last9 should appear as connected or needs authentication
```

## Development

```shell
npm install
npm test        # unit tests (tsx --test)
npm run typecheck
npm pack --dry-run   # regenerates skills/ via prepack, then lists the tarball
```

Bundled `skills/` are generated from the repository-root canonical tree by the
`prepack` hook — never commit that directory.

The plugin entrypoint must export **only functions** — opencode's loader rejects modules with non-function exports.

## License

MIT — see the repo root [LICENSE](../../LICENSE).
