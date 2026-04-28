#!/usr/bin/env bash
# SessionStart hook for cs.
# Записывает session_id текущего Claude Code в файл, проиндексированный по
# имени tmux-сокета. Используется `cs switch` для продолжения той же беседы
# через `--resume <session_id>` после респавна окна.

set -u

input="$(cat)"
session_id="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)"

if [ -z "$session_id" ] || [ -z "${TMUX:-}" ]; then
  exit 0
fi

socket_path="${TMUX%%,*}"
socket_name="$(basename "$socket_path")"
dir="$HOME/.local/share/claude-shared/tmux-switch"
mkdir -p "$dir"
printf '%s' "$session_id" > "$dir/$socket_name"
exit 0
