#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

install_link() {
  local source_dir="$1"
  local dest="$2"
  mkdir -p "$(dirname "$dest")"
  if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$source_dir" ]; then
    echo "Already installed: $dest"
    return
  fi
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    echo "Refusing to replace existing path: $dest" >&2
    exit 1
  fi
  ln -s "$source_dir" "$dest"
  echo "Installed: $dest -> $source_dir"
}

for source_dir in "$root"/skills/*; do
  [ -d "$source_dir" ] || continue
  name="$(basename "$source_dir")"
  install_link "$source_dir" "$HOME/.agents/skills/$name"
  install_link "$source_dir" "$HOME/.claude/skills/$name"
  install_link "$source_dir" "${CODEX_HOME:-$HOME/.codex}/skills/$name"
done

echo "OpenCode uses the shared $HOME/.agents/skills links (no duplicate OpenCode links created)."
