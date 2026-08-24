#!/usr/bin/env sh
# Verifies skill distribution correctness for the repo-as-hub model:
#   1. every tracked skills/*/SKILL.md has frontmatter name == directory name
#   2. every marketplace manifest's declared skills paths exist in the tree
#   3. the opencode plugin tarball contains every tracked canonical skill
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT_DIR"

# 1. Frontmatter name must equal the skill directory name.
for skill_md in $(git ls-files 'skills/*/SKILL.md'); do
  dir="$(basename "$(dirname "$skill_md")")"
  expected_name="$(sed -n 's/^name: //p' "$skill_md")"
  if [ "$expected_name" != "$dir" ]; then
    echo "::error::Skill directory/name mismatch: $skill_md declares name '$expected_name'" >&2
    exit 1
  fi
done

# 2. Declared marketplace skills paths must exist.
for manifest in .claude-plugin/marketplace.json .agents/plugins/marketplace.json; do
  [ -f "$manifest" ] || continue
  for path in $(jq -r '.plugins[]?.skills[]?' "$manifest" 2>/dev/null); do
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
