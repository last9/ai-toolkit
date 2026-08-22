#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
PLUGIN_DIRS="$ROOT_DIR/plugins/last9 $ROOT_DIR/plugins/opencode-last9"

for PLUGIN_DIR in $PLUGIN_DIRS; do
  if [ -f "$PLUGIN_DIR/.codex-plugin/plugin.json" ]; then
    jq -e '.skills == "./skills/"' "$PLUGIN_DIR/.codex-plugin/plugin.json" >/dev/null
  fi

  # Regenerate the packaged skills as an exact mirror of canonical skills/:
  # new skills are discovered automatically, deleted skills leave no stale copy.
  rm -rf "$PLUGIN_DIR/skills"
  mkdir -p "$PLUGIN_DIR/skills"

  for skill_dir in "$ROOT_DIR"/skills/*/; do
    skill="$(basename "$skill_dir")"
    expected_name="$(sed -n 's/^name: //p' "$ROOT_DIR/skills/$skill/SKILL.md")"
    test "$expected_name" = "$skill"

    mkdir -p "$PLUGIN_DIR/skills/$skill"
    cp "$ROOT_DIR/skills/$skill/SKILL.md" "$PLUGIN_DIR/skills/$skill/SKILL.md"
    cmp "$ROOT_DIR/skills/$skill/SKILL.md" "$PLUGIN_DIR/skills/$skill/SKILL.md" >/dev/null
  done
done

echo "last9 agent plugin skills synced"
