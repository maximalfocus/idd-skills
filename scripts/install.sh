#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_dir="$root/skills/idd"

install_link() {
  local dest="$1"
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

install_link "$HOME/.agents/skills/idd"
install_link "$HOME/.claude/skills/idd"
install_link "${CODEX_HOME:-$HOME/.codex}/skills/idd"
