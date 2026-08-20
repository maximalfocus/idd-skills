#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
codex_home="${CODEX_HOME:-$HOME/.codex}"
sources=()
destinations=()
created_sources=()
created_destinations=()
preflight_failed=0

add_destination() {
  local source_dir="$1" dest="$2" existing
  for existing in "${destinations[@]:-}"; do
    [ "$existing" != "$dest" ] || return
  done
  sources+=("$source_dir")
  destinations+=("$dest")
}

nearest_existing_parent() {
  local path="$1" parent
  parent="$(dirname "$path")"
  while [ ! -e "$parent" ] && [ ! -L "$parent" ]; do
    path="$parent"
    parent="$(dirname "$path")"
    [ "$parent" != "$path" ] || break
  done
  printf '%s\n' "$parent"
}

rollback() {
  local status="$?" index dest source
  trap - ERR INT TERM
  for ((index=${#created_destinations[@]} - 1; index >= 0; index--)); do
    dest="${created_destinations[$index]}"
    source="${created_sources[$index]}"
    if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$source" ]; then
      unlink "$dest"
      echo "Rolled back: $dest" >&2
    else
      echo "Rollback stopped at changed path: $dest" >&2
    fi
  done
  exit "$status"
}

for source_dir in "$root"/skills/*; do
  [ -d "$source_dir" ] || continue
  name="$(basename "$source_dir")"
  if [ ! -f "$source_dir/SKILL.md" ]; then
    echo "Invalid skill source (missing SKILL.md): $source_dir" >&2
    preflight_failed=1
  fi
  add_destination "$source_dir" "$HOME/.agents/skills/$name"
  add_destination "$source_dir" "$HOME/.claude/skills/$name"
  add_destination "$source_dir" "$codex_home/skills/$name"
done

[ "${#sources[@]}" -gt 0 ] || { echo "No skill sources found under $root/skills" >&2; exit 1; }

for ((index=0; index<${#destinations[@]}; index++)); do
  source_dir="${sources[$index]}"
  dest="${destinations[$index]}"
  if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$source_dir" ]; then
    continue
  fi
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    echo "Refusing to replace existing path: $dest" >&2
    preflight_failed=1
    continue
  fi
  parent="$(nearest_existing_parent "$dest")"
  if [ ! -d "$parent" ]; then
    echo "Destination parent is not a directory: $parent (for $dest)" >&2
    preflight_failed=1
  elif [ ! -w "$parent" ]; then
    echo "Destination parent is not writable: $parent (for $dest)" >&2
    preflight_failed=1
  fi
done

[ "$preflight_failed" -eq 0 ] || exit 1

trap rollback ERR INT TERM
for ((index=0; index<${#destinations[@]}; index++)); do
  source_dir="${sources[$index]}"
  dest="${destinations[$index]}"
  if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$source_dir" ]; then
    echo "Already installed: $dest"
    continue
  fi
  mkdir -p "$(dirname "$dest")"
  ln -s "$source_dir" "$dest"
  created_sources+=("$source_dir")
  created_destinations+=("$dest")
  echo "Installed: $dest -> $source_dir"
done
trap - ERR INT TERM

echo "OpenCode and Pi use the shared $HOME/.agents/skills links."
