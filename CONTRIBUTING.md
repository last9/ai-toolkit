# Contributing to Last9 AI Toolkit

Thanks for contributing! This repo ships AI-agent skills and plugin packages for Claude Code, Cursor, OpenAI Codex, and skills.sh.

## The canonical-source model

The top-level `skills/` directory is the **single source of truth**. The plugin package copies under `plugins/last9/skills/` are **generated** — never edit them directly.

When you change a skill:

1. Edit the skill under `skills/<skill-name>/SKILL.md`.
2. Run the sync script:

   ```shell
   scripts/sync-agent-plugin-skills.sh
   ```

3. Commit both the canonical file and the regenerated plugin copy together.

CI enforces parity: if the generated copies drift from `skills/`, the sync-parity check fails your PR.

## Commit convention

Use [Conventional Commits](https://www.conventionalcommits.org/): `feat:`, `fix:`, `docs:`, `chore:`, `refactor:`, optionally scoped (e.g., `feat(skills): ...`).

## CI checks on your PR

Every PR runs:

- **Secret scan** (gitleaks) — blocks credentials, tokens, and key-shaped strings. Documented placeholders like `<org-slug>` and `<your-api-key>` are allowlisted.
- **Structural reference scan** — blocks real org slugs (use `<org-slug>`), internal source-path citations, and bare commit-SHA citations.
- **Sync parity** — verifies `plugins/last9/skills/` matches `skills/`.

### A note for fork PRs

One additional scan (a forbidden-term check against a private denylist) cannot run on PRs from forks — GitHub does not expose repository secrets to fork workflows. On fork PRs that check reports a visible "skipped — runs on merge" status, and a maintainer runs it manually against your branch before merging. A green checkmark on a fork PR therefore does not by itself mean every check has passed — this is a GitHub platform limitation, not something you need to act on.

## Adding a new skill

- Directory name must equal the `name:` field in the SKILL.md frontmatter (the sync script enforces this).
- Follow the existing SKILL.md structure: YAML frontmatter (`name`, `description` with explicit trigger phrases, `compatibility`, `metadata.author`), operating principle, prerequisites, guardrail/anti-pattern table, methodology, reference card, related-skills cross-reference.
- Cite only public sources in verification notes — no internal file paths, no private commit SHAs.

## What not to include

- Secrets, tokens, API keys, credentials — use placeholders (`<your-api-key>`, `${env:SECRET}`).
- Real organization slugs in URLs — use `<org-slug>`.
- Internal Last9 implementation details, internal repo names, or customer names.
- Binary files.
