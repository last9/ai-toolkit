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
    "prepack": "mkdir -p skills && for d in ../../skills/*/; do n=$(basename $d); mkdir -p skills/$n; cp ${d}SKILL.md skills/$n/SKILL.md; done"
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

echo "check-skill-pack selftests passed"
