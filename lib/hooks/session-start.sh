#!/usr/bin/env bash
# SessionStart hook for cs.
# Сохраняет session_id текущего Claude Code в state-файл, ключеванный по
# (tmux-socket, pane_id, pwd, account). cs switch читает его обратно и через
# `claude --resume` продолжает ту же беседу в том же пэйне для того же проекта.
#
# Путь state-файла:
#   ~/.local/share/claude-shared/tmux-switch/<socket>.p<pane>.<pwdhash>.<account>

set -u

input="$(cat)"
session_id="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)"
cwd_in="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"

[ -z "$session_id" ] && exit 0
[ -z "${TMUX:-}" ] && exit 0

# account ← CLAUDE_CONFIG_DIR
account=""
if [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then
    base="$(basename "$CLAUDE_CONFIG_DIR")"
    case "$base" in claude-*) account="${base#claude-}" ;; esac
fi
[ -z "$account" ] && exit 0

# tmux socket
socket_path="${TMUX%%,*}"
socket_name="$(basename "$socket_path")"

# pane_id (из env или через tmux display)
pane_id="${TMUX_PANE:-}"
[ -z "$pane_id" ] && pane_id="$(tmux display -p '#{pane_id}' 2>/dev/null || true)"
pane_id="${pane_id#%}"
[ -z "$pane_id" ] && exit 0

# pwd hash. Источник истины — $PWD env var (ровно то же читает cmd_switch).
# input.cwd оставлен только как фолбэк, если PWD пустой.
pwd_val="${PWD:-${cwd_in:-/}}"
pwd_hash="$(printf '%s' "$pwd_val" | cksum | cut -d' ' -f1)"

dir="$HOME/.local/share/claude-shared/tmux-switch"
mkdir -p "$dir"
state_path="$dir/$socket_name.p$pane_id.$pwd_hash.$account"
printf '%s' "$session_id" > "$state_path"

# debug log — одна строка для пары «hook write» / «switch read».
log_file="$HOME/.local/share/claude-shared/cs.log"
printf '%s hook  s=%s p=%s h=%s a=%s sid=%s pwd=%s\n' \
    "$(date +%s)" "$socket_name" "$pane_id" "$pwd_hash" "$account" "$session_id" "$pwd_val" \
    >> "$log_file" 2>/dev/null || true

exit 0
