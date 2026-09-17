#!/usr/bin/env bash
# Installs superclaude-springboot skills into a target Spring Boot project.
# Usage: ./install.sh <target-project-path>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$SCRIPT_DIR/skills"

if [ $# -lt 1 ]; then
  echo "Usage: $0 <target-project-path>" >&2
  exit 1
fi

TARGET_PROJECT="$1"
if [ ! -d "$TARGET_PROJECT" ]; then
  echo "Error: target path does not exist: $TARGET_PROJECT" >&2
  exit 1
fi

DEST_DIR="$TARGET_PROJECT/.claude/skills"
mkdir -p "$DEST_DIR"

for skill_path in "$SOURCE_DIR"/*/; do
  skill_name="$(basename "$skill_path")"
  target_path="$DEST_DIR/$skill_name"

  if [ -e "$target_path" ]; then
    read -r -p "'$skill_name' already exists. Overwrite? [y/N] " answer
    if [[ ! "$answer" =~ ^[Yy]$ ]]; then
      echo "Skipped: $skill_name"
      continue
    fi
    rm -rf "$target_path"
  fi

  cp -r "$skill_path" "$target_path"
  echo "Installed: $skill_name -> $target_path"
done

echo "Done. Skills installed in $DEST_DIR:"
ls -1 "$DEST_DIR"
