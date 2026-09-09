#!/usr/bin/env sh
# Negative tests for check-skill-pack.sh: each fail-closed branch must exit 1
# on a seeded fault, and a clean fixture must pass. Runs in temp git repos.
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/skill-pack-selftest.XXXXXX")"
trap 'rm -rf "$SANDBOX"' EXIT

setup_fixture() {
  FIX="$SANDBOX/$1"
  mkdir -p "$FIX/scripts" \
    "$FIX/.claude-plugin" \
    "$FIX/.agents/plugins" \
    "$FIX/.codex-plugin" \
    "$FIX/skills/last9-logs" \
    "$FIX/plugins/opencode-last9"
  cp "$ROOT_DIR/scripts/check-skill-pack.sh" "$FIX/scripts/"
  cat > "$FIX/plugins/opencode-last9/package.json" <<'PKG'
{
  "name": "opencode-last9",
  "version": "0.0.0-test",
  "scripts": {
    "prepack": "mkdir -p skills && cp -R ../../skills/. skills/"
  }
}
PKG
  printf -- '---\nname: last9-logs\ndescription: x\n---\nbody\n' > "$FIX/skills/last9-logs/SKILL.md"
  printf '{"plugins":[{"name":"last9","source":"./","skills":["./skills/"]}]}' > "$FIX/.claude-plugin/marketplace.json"
  printf '{"plugins":[{"name":"last9","source":{"source":"local","path":"./"}}]}' > "$FIX/.agents/plugins/marketplace.json"
  printf '{"name":"last9","skills":"./skills/"}' > "$FIX/.codex-plugin/plugin.json"
  (cd "$FIX" && git init -q && git add -A && git -c user.email=t@t -c user.name=t commit -qm base)
}

# Full-strength invocation: pin the environment so a caller's exported
# SKIP_MIRROR_PARITY (CI sets it on PRs) cannot leak into these cases.
run_full() {
  env -u SKIP_MIRROR_PARITY "$@"
}

expect_fail() {
  if run_full sh "$FIX/scripts/check-skill-pack.sh" >/dev/null 2>&1; then
    echo "selftest FAILED: $1 expected exit 1, got 0" >&2
    exit 1
  fi
}

commit_fault() {
  git -C "$FIX" add -A && git -C "$FIX" -c user.email=t@t -c user.name=t commit -qm fault
}

# Branch 1: frontmatter name != directory name.
setup_fixture name-mismatch
printf -- '---\nname: wrong-name\n---\n' > "$FIX/skills/last9-logs/SKILL.md"
commit_fault
expect_fail "name mismatch"

# Branch 2: manifest declares a skills path that does not exist.
setup_fixture missing-path
printf '{"plugins":[{"name":"last9","source":"./","skills":["./nope/"]}]}' > "$FIX/.claude-plugin/marketplace.json"
commit_fault
expect_fail "missing declared path"

# Branch 3: malformed manifest JSON must fail closed, not silently skip.
setup_fixture bad-json
printf '{"name":"last9", broken' > "$FIX/.claude-plugin/marketplace.json"
commit_fault
expect_fail "malformed manifest JSON"

# Branch 4: string-typed skills must not false-pass directory checks.
setup_fixture string-skills
printf '{"plugins":[{"name":"last9","source":"./","skills":"./skills/"}]}' > "$FIX/.claude-plugin/marketplace.json"
commit_fault
expect_fail "string-typed skills"

# Branch 5: deleting a consumer manifest must fail closed.
setup_fixture deleted-manifest
rm "$FIX/.claude-plugin/marketplace.json"
git -C "$FIX" rm -q .claude-plugin/marketplace.json
expect_fail "deleted manifest"

# Branch 7: codex plugin skills pointer drift.
setup_fixture codex-drift
printf '{"name":"last9","skills":"./wrong/"}' > "$FIX/.codex-plugin/plugin.json"
commit_fault
expect_fail "codex pointer drift"

# Happy path: clean fixture passes at full strength.
setup_fixture happy
if ! run_full sh "$FIX/scripts/check-skill-pack.sh" >/dev/null 2>&1; then
  echo "selftest FAILED: clean fixture expected exit 0" >&2
  exit 1
fi

# Committed plugin skill copies must fail (hub invariant).
setup_fixture committed-copy
mkdir -p "$FIX/plugins/acme/skills/rogue"
cp "$FIX/skills/last9-logs/SKILL.md" "$FIX/plugins/acme/skills/rogue/SKILL.md"
git -C "$FIX" add -A && git -C "$FIX" -c user.email=t@t -c user.name=t commit -qm fault
expect_fail "committed plugin skill copy"

# References must ship exactly when tracked, without permitting arbitrary payloads.
setup_fixture reference-happy
mkdir -p "$FIX/skills/last9-logs/references"
printf 'focused reference\n' > "$FIX/skills/last9-logs/references/family.md"
commit_fault
if ! run_full sh "$FIX/scripts/check-skill-pack.sh" >/dev/null 2>&1; then
  echo "selftest FAILED: tracked Markdown reference expected exit 0" >&2
  exit 1
fi

setup_fixture reference-missing
mkdir -p "$FIX/skills/last9-logs/references"
printf 'focused reference\n' > "$FIX/skills/last9-logs/references/family.md"
commit_fault
# Simulate a packer that omits a tracked reference.
jq '.scripts.prepack += " && rm skills/last9-logs/references/family.md"' "$FIX/plugins/opencode-last9/package.json" > "$FIX/package.tmp"
mv "$FIX/package.tmp" "$FIX/plugins/opencode-last9/package.json"
expect_fail "missing packaged reference"

setup_fixture reference-untracked
mkdir -p "$FIX/skills/last9-logs/references"
printf 'untracked experiment\n' > "$FIX/skills/last9-logs/references/untracked.md"
expect_fail "untracked packaged reference"

setup_fixture arbitrary-payload
mkdir -p "$FIX/skills/last9-logs/scripts"
printf 'echo unexpected\n' > "$FIX/skills/last9-logs/scripts/run.sh"
commit_fault
expect_fail "arbitrary tracked script"

setup_fixture reference-symlink
mkdir -p "$FIX/skills/last9-logs/references"
printf 'outside skill\n' > "$FIX/outside.md"
ln -s ../../../outside.md "$FIX/skills/last9-logs/references/escape.md"
commit_fault
expect_fail "tracked reference symlink"

setup_fixture reference-parent-symlink
mkdir -p "$FIX/skills/last9-logs/references"
printf 'focused reference\n' > "$FIX/skills/last9-logs/references/family.md"
commit_fault
mv "$FIX/skills/last9-logs/references" "$FIX/outside-references"
ln -s ../../outside-references "$FIX/skills/last9-logs/references"
expect_fail "working-tree reference parent symlink"

setup_fixture reference-without-entrypoint
mkdir -p "$FIX/skills/orphan/references"
printf 'orphan\n' > "$FIX/skills/orphan/references/family.md"
commit_fault
expect_fail "reference without entrypoint"

# The gate must never delete or inspect another invocation's archive.
setup_fixture archive-isolation
ARCHIVE_TMP="$SANDBOX/archive-temp"
mkdir -p "$ARCHIVE_TMP"
printf 'unrelated archive\n' > "$ARCHIVE_TMP/sentinel.tgz"
if ! TMPDIR="$ARCHIVE_TMP" run_full sh "$FIX/scripts/check-skill-pack.sh" >/dev/null 2>&1; then
  echo "selftest FAILED: isolated archive pack expected exit 0" >&2
  exit 1
fi
if [ ! -f "$ARCHIVE_TMP/sentinel.tgz" ] || [ "$(cat "$ARCHIVE_TMP/sentinel.tgz")" != "unrelated archive" ]; then
  echo "selftest FAILED: unrelated archive was changed or deleted" >&2
  exit 1
fi

echo "check-skill-pack selftests passed"
