# Last9 AI Toolkit

[![OSS guardrails](https://github.com/last9/ai-toolkit/actions/workflows/oss-guardrails.yml/badge.svg)](https://github.com/last9/ai-toolkit/actions/workflows/oss-guardrails.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

AI agents are good at writing queries and bad at knowing which query to write. This toolkit teaches coding agents — Claude Code, Codex, Grok Build, Cursor, and anything that speaks [Agent Skills](https://skills.sh) — how to instrument and investigate production systems with [Last9](https://last9.io): which tool to reach for, in what order, and which dead ends to skip.

Each skill encodes a workflow the way the product intends it — the skills hand off to one another when work crosses domains.

## Skills

MCP gives your agent access. Skills give it judgment.

| Skill | What it teaches |
|-------|-----------------|
| [`go-agent-install`](skills/go-agent-install/SKILL.md) | Instrument a Go service with Last9 go-agent: detect the stack, wire chi + `database/sql` tracing, promote opt-in body capture, and verify spans land — without double-instrumenting |
| [`last9-logs`](skills/last9-logs/SKILL.md) | Log investigation: scope to a service first, attribute filters over body search, aggregate before drilling into raw lines |
| [`last9-traces`](skills/last9-traces/SKILL.md) | Trace investigation: a five-question interview that lands on the right tool call, plus a `tracejson` syntax reference card |

## Installation

```shell
npx skills add last9/ai-toolkit
```

Install a single skill, or target a specific agent:

```shell
npx skills add last9/ai-toolkit --skill last9-logs
npx skills add last9/ai-toolkit -a claude-code
```

Claude Code and Codex install through their marketplaces, which resolve skills directly from this repository's canonical `skills/` tree. Grok Build installs straight from the plugin subdirectory:

```shell
grok plugin install --trust "last9/ai-toolkit#plugins/last9"
```

OpenCode users get MCP registration plus skills from a single plugin:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "plugin": [["opencode-last9", { "org": "<org-slug>" }]]
}
```

Then run `opencode mcp auth last9` once to authenticate. See [`plugins/opencode-last9/`](plugins/opencode-last9/) for details.

## Connecting to Last9

Last9 MCP is hosted, so there is no local server to run. Point your agent's MCP config at your organization's endpoint. For Codex:

```toml
[mcp_servers.last9]
url = "https://app.last9.io/api/v4/organizations/<org-slug>/mcp"
```

For Claude Code, add the same endpoint through its MCP configuration flow. Then run `/mcp` to authenticate. Keep local MCP config files (`.codex/config.toml`, `.claude/settings.local.json`) out of version control.

## Contributing

The top-level `skills/` directory is the single source of truth: marketplace manifests reference it directly and the OpenCode plugin assembles it into its tarball at pack time, so adding a skill is a single commit under `skills/<name>/`. CI validates distribution correctness (naming, declared paths, tarball completeness). See [CONTRIBUTING.md](CONTRIBUTING.md) for the workflow, and [SECURITY.md](SECURITY.md) for reporting vulnerabilities.

## License

Last9 AI Toolkit is released under the [MIT License](LICENSE).
