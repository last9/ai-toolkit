# Last9 Agent Plugin

Public Codex, Claude Code, and Grok Build plugin package for Last9 observability workflows.

This plugin packages the Last9 skills for agent marketplaces:

- `last9-logs` — log-first investigation and logjson guardrails.
- `last9-traces` — trace-first investigation and tracejson guardrails.

Claude Code and Codex read root-level marketplace manifests that point at the canonical repository-root `skills/` directory directly — adding a skill is a single commit under `skills/<name>/`. Grok Build’s installer cannot follow root sources, so it installs from this package directory: its skills mirror is refreshed automatically by CI after merge, so contributors still only touch `skills/`.

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
