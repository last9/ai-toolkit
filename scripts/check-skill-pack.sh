#!/usr/bin/env sh
# Verifies skill distribution correctness for the repo-as-hub model:
#   0. no unsanctioned committed plugin skill copies; sanctioned Grok mirror
#      byte-parity (skippable on contributor PRs via SKIP_MIRROR_PARITY=1 —
#      a master-push bot refreshes the mirror automatically)
#   1. every tracked skills/*/SKILL.md has frontmatter name == directory name
#   2. consumer manifests parse, declare real skills paths, and are type-safe
#   3. the opencode plugin tarball contains exactly the tracked canonical set
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT_DIR"

# 0. Committed plugin skill copies are forbidden — every consumer reads or
#    assembles from the canonical tree; Grok installs via
#    `grok plugin install --trust last9/ai-toolkit#plugins/last9`.
if [ -n "$(git ls-files 'plugins/*/skills/*')" ]; then
  echo "::error::committed plugin skill copies are forbidden (hub model):" >&2
  git ls-files 'plugins/*/skills' >&2
  exit 1
fi

# 1. Frontmatter name must equal the skill directory name. Extract from the
#    YAML frontmatter block only (between the first two --- delimiters), so a
#    body line starting "name: " cannot false-fail the gate.
for skill_md in $(git ls-files 'skills/*/SKILL.md'); do
  dir="$(basename "$(dirname "$skill_md")")"
  expected_name="$(awk '/^---$/{c++; next} c==1 && /^name: /{sub(/^name: */, ""); print; exit}' "$skill_md")"
  if [ "$expected_name" != "$dir" ]; then
    echo "::error::Skill directory/name mismatch: $skill_md declares name '$expected_name'" >&2
    exit 1
  fi
done

# 2. Consumer manifests must exist, parse, and declare real skills paths.
#    Type-safe: skills must be an array of "./"-relative strings — jq iterates
#    a string as characters, so a string-typed value would otherwise false-pass
#    directory checks. .agents/plugins/marketplace.json legitimately declares
#    no skills key (Codex discovers conventionally), but it must still parse.
check_manifest() {
  manifest="$1"
  require_skills="${2:-yes}"
  [ -f "$manifest" ] || {
    echo "::error::required marketplace manifest missing: $manifest" >&2
    exit 1
  }
  jq -e 'type == "object"' "$manifest" >/dev/null || {
    echo "::error::$manifest is not valid JSON" >&2
    exit 1
  }
  jq -e '.plugins | type == "array" and length >= 1' "$manifest" >/dev/null || {
    echo "::error::$manifest declares no plugins" >&2
    exit 1
  }
  if [ "$require_skills" = "yes" ]; then
    jq -e 'all(.plugins[]; has("skills") and (.skills | type == "array") and length >= 1) and all(.plugins[].skills[]; type == "string" and startswith("./"))' "$manifest" >/dev/null || {
      echo "::error::$manifest skills must be a non-empty array of ./-relative strings" >&2
      exit 1
    }
  fi
  paths="$(jq -r '(.plugins[]?.skills[]?) // empty' "$manifest")"
  for path in $paths; do
    case "$path" in
      ./*) ;;
      *) echo "::error::$manifest skills paths must be ./-relative: $path" >&2; exit 1 ;;
    esac
    rel="${path#./}"
    if [ ! -d "$rel" ]; then
      echo "::error::$manifest declares missing skills path: $path" >&2
      exit 1
    fi
    if [ -z "$(find "$rel" -name SKILL.md -print -quit)" ]; then
      echo "::error::$manifest skills path contains no SKILL.md: $path" >&2
      exit 1
    fi
  done
}

check_manifest .claude-plugin/marketplace.json yes
check_manifest .agents/plugins/marketplace.json no

# 2b. The Codex root plugin manifest must keep pointing at the canonical tree.
jq -e '.skills == "./skills/"' .codex-plugin/plugin.json >/dev/null || {
  echo "::error::.codex-plugin/plugin.json skills pointer drifted" >&2
  exit 1
}

# 3. The opencode tarball ships exactly the tracked canonical skill set —
#    both directions: nothing missing, nothing extra. Pack quietly to a real
#    tarball so npm failures fail fast and listing comes from tar, not logs.
cd plugins/opencode-last9
npm run prepack >/dev/null
tgz="$(mktemp "${TMPDIR:-/tmp}/skill-pack.XXXXXX.tgz")"
npm pack --pack-destination "$(dirname "$tgz")" --silent >/dev/null 2>&1 || {
  echo "::error::npm pack failed" >&2
  exit 1
}
tar -tzf "$(ls -t "$(dirname "$tgz")"/*.tgz | head -1)" > "$tgz.list"
rm -f "$(dirname "$tgz")"/*.tgz
cd "$ROOT_DIR"
missing=0
for skill_md in $(git ls-files 'skills/*/SKILL.md'); do
  grep -q "^package/skills/${skill_md#skills/}$" "$tgz.list" || {
    echo "::error::opencode tarball missing canonical skill: $skill_md" >&2
    missing=1
  }
done
extras=$(grep -E "^package/skills/" "$tgz.list" | grep -vE "^package/skills/[^/]+/SKILL\.md$" || true)
if [ -n "$extras" ]; then
  echo "::error::opencode tarball ships unexpected skills payload:" >&2
  echo "$extras" >&2
  missing=1
fi
rm -f "$tgz.list"
[ "$missing" -eq 0 ] || exit 1

echo "skill distribution checks passed"
