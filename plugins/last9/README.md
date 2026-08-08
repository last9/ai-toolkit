# Last9 Agent Plugin

Public Agent Plugins package for Last9 observability workflows, installable in Claude Code, Codex, Grok Build, and any client that implements the open [Agent Plugins](https://agent-plugins.org) standard (v1.0.0).

This plugin packages the Last9 skills for agent marketplaces:

- `last9-logs` — log-first investigation and logjson guardrails.
- `last9-traces` — trace-first investigation and tracejson guardrails.

This directory *is* the plugin root. `plugin.json` at its root is the spec-conformant [Agent Plugins](https://agent-plugins.org/specification) manifest — any compatible client discovers it there and reads skills from the fixed `skills/` location, with no client-specific configuration needed. Claude Code, Codex, and Grok Build predate that standard and still read their own manifests instead — `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, and `.grok-plugin/plugin.json` (whose format mirrors Claude Code's) — which is why all four coexist here. The top-level `skills/` directory remains the canonical source. The package-local `skills/` directory is generated from it by `scripts/sync-agent-plugin-skills.sh` so marketplace installs are self-contained without hand-maintained drift.

If you are using the Agent Skills CLI or skills.sh directly, install from the repository root instead:

```shell
npx skills add last9/ai-toolkit
npx skills add last9/ai-toolkit --skill last9-logs
npx skills add last9/ai-toolkit --skill last9-traces
```

The plugin does not bundle or launch a local MCP server. Last9 MCP is hosted; configure your agent to connect to your organization's hosted endpoint.

## Hosted MCP Configuration

Add the hosted MCP endpoint to your local agent MCP config. For Codex:

```toml
[mcp_servers.last9]
url = "https://app.last9.io/api/v4/organizations/<org-slug>/mcp"
```

For Claude Code, add the same hosted endpoint through Claude Code's MCP configuration flow. For Grok Build, add the same hosted endpoint through its MCP configuration (a `.mcp.json` entry or the in-terminal MCP flow).

Then start your agent and run `/mcp` to authenticate.

Do not commit local `.codex/config.toml`, `.claude/settings.local.json`, or equivalent MCP config files. They are user- and organization-specific.

## Skill Boundaries

- Use `last9-logs` for log-first investigation: service/env surfacing, attribute discovery, aggregate-then-drill, body search only after narrowing.
- Use `last9-traces` for trace-first investigation: guided service/env/time/symptom/scope interview plus tracejson reference.
