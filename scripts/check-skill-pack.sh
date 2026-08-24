#!/usr/bin/env sh
# Verifies skill distribution correctness for the repo-as-hub model:
#   1. every tracked skills/*/SKILL.md has frontmatter name == directory name
#   2. every marketplace manifest's declared skills paths exist in the tree
#   3. the opencode plugin tarball contains every tracked canonical skill
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT_DIR"

# 0. No committed plugin skill copies — mirrors resurrect easily when a
#    pack-time regeneration runs between staging and committing.
if [ -n "$(git ls-files 'plugins/*/skills')" ]; then
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
