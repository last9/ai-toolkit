# Last9 Agent Plugin

Public Codex, Claude Code, and Grok Build plugin package for Last9 observability workflows.

This plugin packages the Last9 skills for agent marketplaces:

- `last9-logs` — log-first investigation and logjson guardrails.
- `last9-traces` — trace-first investigation and tracejson guardrails.

Each agent reads the same package through its own manifest — `.claude-plugin/plugin.json` for Claude Code, `.codex-plugin/plugin.json` for Codex, and `.grok-plugin/plugin.json` for Grok Build (whose plugin format mirrors Claude Code's). The top-level `skills/` directory remains the canonical source. The package-local `skills/` directory is generated from it by `scripts/sync-agent-plugin-skills.sh` so marketplace installs are self-contained without hand-maintained drift.

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
