#!/usr/bin/env bash
# stop-limit-detector.sh — Stop hook for Claude Code.
#
# Reads Stop event payload from stdin (Claude Code passes JSON), detects
# signals that the current account is approaching/at usage limit, writes
# limit-signal/<account>.json для cs-auto-switch orchestrator.
#
# Detection signals:
#   1. stop_reason содержит "limit" / "exhausted" / "rate_limit" / "quota"
#   2. Recent cost surge (cost-tracker.py JSONL last 3 entries) — heuristic
#   3. Parsed cs usage cache — at_limit:true OR pct >= 90%
#
# Async, fast, fail-open. Exit 0 always (don't block Stop event).
#
# Wire в каждом account's settings.json:
#   "hooks": { "Stop": [{ "matcher": "*", "hooks": [{
#     "type": "command", "command": "bash $HOME/.local/share/cs-shared/lib/hooks/stop-limit-detector.sh"
#   }]}]}
#
# (Auto-wired by `cs auto-switch enable` / `cs add --auto-switch`.)

set +e

# Read input (Claude Code Stop event JSON)
input="$(cat)"

# Extract account from CLAUDE_CONFIG_DIR (set by cs switch)
ACCOUNT=""
if [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then
    base="$(basename "$CLAUDE_CONFIG_DIR")"
    case "$base" in claude-*) ACCOUNT="${base#claude-}" ;; esac
fi

# If not cs-managed, exit silently
[ -z "$ACCOUNT" ] && exit 0

SHARED_DIR="$HOME/.local/share/claude-shared"
SIGNAL_DIR="$SHARED_DIR/auto-switch/limit-signal"
USAGE_CACHE="$SHARED_DIR/usage-cache"
LOG_FILE="$HOME/.claude/logs/stop-limit-detector.log"

mkdir -p "$SIGNAL_DIR" "$(dirname "$LOG_FILE")" 2>/dev/null

_log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] [$ACCOUNT] $*" >> "$LOG_FILE"; }

# ─── Signal 1: stop_reason text match ────────────────────────────────────────
stop_reason=$(echo "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('stop_reason') or '')" 2>/dev/null)

at_limit_text=false
if [ -n "$stop_reason" ]; then
    if echo "$stop_reason" | grep -qiE "(limit|exhaust|rate_limit|quota|reached)"; then
        at_limit_text=true
        _log "stop_reason limit signal: $stop_reason"
    fi
fi

# ─── Signal 2: parsed usage cache (если есть recent) ─────────────────────────
at_limit_cache=false
session_pct=null
week_pct=null
parsed_cache="$USAGE_CACHE/$ACCOUNT.parsed.json"
if [ -f "$parsed_cache" ]; then
    cache_age=$((  $(date +%s) - $(stat -f "%m" "$parsed_cache" 2>/dev/null || echo 0) ))
    # Use cache only if <30 min old
    if [ "$cache_age" -lt 1800 ]; then
        cache_data=$(cat "$parsed_cache")
        at_limit_cache=$(echo "$cache_data" | python3 -c "import sys,json; print(str(json.load(sys.stdin).get('at_limit', False)).lower())" 2>/dev/null)
        session_pct=$(echo "$cache_data" | python3 -c "import sys,json; v=json.load(sys.stdin).get('session_pct'); print(v if v is not None else 'null')" 2>/dev/null)
        week_pct=$(echo "$cache_data" | python3 -c "import sys,json; v=json.load(sys.stdin).get('week_pct'); print(v if v is not None else 'null')" 2>/dev/null)
    fi
fi

# Threshold check (90%)
threshold_hit=false
if [ "$session_pct" != "null" ]; then
    if awk -v p="$session_pct" 'BEGIN { exit !(p >= 90) }'; then
        threshold_hit=true
    fi
fi
if [ "$week_pct" != "null" ]; then
    if awk -v p="$week_pct" 'BEGIN { exit !(p >= 90) }'; then
        threshold_hit=true
    fi
fi

# ─── Decision ────────────────────────────────────────────────────────────────
should_signal=false
reason=""
if [ "$at_limit_text" = "true" ]; then
    should_signal=true
    reason="stop_reason"
elif [ "$at_limit_cache" = "true" ]; then
    should_signal=true
    reason="cache_at_limit"
elif [ "$threshold_hit" = "true" ]; then
    should_signal=true
    reason="threshold_90pct"
fi

if [ "$should_signal" = "false" ]; then
    _log "no signal (stop_reason=$stop_reason, cache_at_limit=$at_limit_cache, threshold_hit=$threshold_hit)"
    exit 0
fi

# ─── Write limit-signal ──────────────────────────────────────────────────────
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
SESSION_ID=$(echo "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('session_id') or '')" 2>/dev/null)

cat > "$SIGNAL_DIR/$ACCOUNT.json" <<EOF
{
  "ts": "$TS",
  "account": "$ACCOUNT",
  "reason": "$reason",
  "session_id": "$SESSION_ID",
  "stop_reason": $(echo "$stop_reason" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().strip()))"),
  "session_pct": $session_pct,
  "week_pct": $week_pct
}
EOF

_log "signaled limit ($reason): session_pct=$session_pct week_pct=$week_pct"

# ─── Optionally trigger auto-switch async ────────────────────────────────────
# Запуск orchestrator'а в background. Lead не блокируется.
if [ -x "$HOME/.local/bin/cs-auto-switch" ]; then
    nohup bash "$HOME/.local/bin/cs-auto-switch" --triggered-by "$reason" >/dev/null 2>&1 &
fi

exit 0
