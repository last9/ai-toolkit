#!/usr/bin/env sh
# Verifies skill distribution correctness for the repo-as-hub model:
#   1. every tracked skills/*/SKILL.md has frontmatter name == directory name
#   2. every marketplace manifest's declared skills paths exist in the tree
#   3. the opencode plugin tarball contains every tracked canonical skill
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT_DIR"

# 0. Committed plugin skill copies are forbidden except the sanctioned
#    Grok fallback mirror (Grok's installer cannot follow root sources or
#    symlinks, so it needs real files inside plugins/last9/).
sanctioned="plugins/last9/skills"
violations="$(git ls-files 'plugins/*/skills' | grep -v "^$sanctioned/" || true)"
if [ -n "$violations" ]; then
  echo "::error::committed plugin skill copies outside the sanctioned Grok fallback:" >&2
  echo "$violations" >&2
  exit 1
fi

# 0b. The sanctioned Grok mirror must match the canonical tree exactly.
for skill_md in $(git ls-files 'skills/*/SKILL.md'); do
  rel="${skill_md#skills/}"
  if [ ! -f "$ROOT_DIR/plugins/last9/skills/$rel" ]; then
    echo "::error::Grok fallback mirror missing canonical skill: $rel" >&2
    exit 1
  fi
  cmp -s "$skill_md" "$ROOT_DIR/plugins/last9/skills/$rel" || {
    echo "::error::Grok fallback mirror drifted from canonical: $rel" >&2
    exit 1
  }
done
for extra in $(git ls-files 'plugins/last9/skills/*'); do
  rel="${extra#plugins/last9/skills/}"
  [ -f "$ROOT_DIR/skills/$rel" ] || {
    echo "::error::Grok fallback mirror has orphaned file: $extra" >&2
    exit 1
  }
done

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

# 2. Manifests must parse, and declared marketplace skills paths must exist.
#    A manifest without a skills key is legal (Codex discovers skills
#    conventionally), but malformed JSON never passes.
for manifest in .claude-plugin/marketplace.json .agents/plugins/marketplace.json; do
  [ -f "$manifest" ] || continue
  jq -e 'type == "object"' "$manifest" >/dev/null || {
    echo "::error::$manifest is not valid JSON" >&2
    exit 1
  }
  paths="$(jq -r '.plugins[]?.skills[]?' "$manifest")" || {
    echo "::error::$manifest could not be parsed for skills paths" >&2
    exit 1
  }
  for path in $paths; do
    rel="${path#./}"
    if [ ! -d "$rel" ]; then
      echo "::error::$manifest declares missing skills path: $path" >&2
      exit 1
    fi
  done
done

# 3. The opencode tarball ships every tracked canonical skill.
cd plugins/opencode-last9
npm run prepack >/dev/null
listing=$(npm pack --dry-run 2>&1)
missing=0
for skill_md in $(git -C "$ROOT_DIR" ls-files 'skills/*/SKILL.md'); do
  name="$(basename "$(dirname "$skill_md")")"
  case "$listing" in
    *"skills/$name/SKILL.md"*) ;;
    *)
      echo "::error::opencode tarball missing canonical skill: $name" >&2
      missing=1
      ;;
  esac
done
[ "$missing" -eq 0 ] || exit 1

echo "skill distribution checks passed"
