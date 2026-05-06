#!/usr/bin/env bash
# cs-parse-usage.sh — parse plaintext output of `claude --print /usage` to
# extract usage percentages.
#
# Usage:
#   cat usage-cache/<account>.txt | bash cs-parse-usage.sh
#   bash cs-parse-usage.sh < cached-output.txt
#
# Output (single line, machine-readable):
#   {"session_pct": <0-100|null>, "week_pct": <0-100|null>, "at_limit": <true|false>, "raw_lines": <count>}
#
# Heuristics — claude /usage plaintext format меняется между versions, поэтому:
#   - Ищем "%" числа около ключевых слов (session, weekly, week, hour)
#   - "limit reached" / "you've used" — at_limit = true
#   - Если ничего не parseable — session_pct=null, week_pct=null, at_limit=false
#
# Не падает на любом input (set +e). Выход всегда 0.

set +e

input="$(cat)"

if [ -z "$input" ]; then
    echo '{"session_pct": null, "week_pct": null, "at_limit": false, "raw_lines": 0}'
    exit 0
fi

raw_lines=$(echo "$input" | wc -l | tr -d ' ')

# Detect at-limit signals (textual)
at_limit=false
if echo "$input" | grep -qiE "(reached|exceeded|exhausted|limit hit|over limit|no remaining)"; then
    at_limit=true
fi

# Parse percentages — multiple strategies
# Strategy 1: explicit "X% used" or "X% of session/week"
session_pct=$(echo "$input" | grep -iE "session" | grep -oE "[0-9]+(\.[0-9]+)?%" | head -1 | tr -d '%')
week_pct=$(echo "$input" | grep -iE "week|weekly|7-day" | grep -oE "[0-9]+(\.[0-9]+)?%" | head -1 | tr -d '%')

# Strategy 2: "X% used" generic (если session/week не нашли отдельно)
if [ -z "$session_pct" ] && [ -z "$week_pct" ]; then
    generic=$(echo "$input" | grep -oE "[0-9]+(\.[0-9]+)?%\s*used" | head -2)
    line1=$(echo "$generic" | sed -n '1p' | grep -oE "[0-9]+(\.[0-9]+)?")
    line2=$(echo "$generic" | sed -n '2p' | grep -oE "[0-9]+(\.[0-9]+)?")
    [ -n "$line1" ] && session_pct="$line1"
    [ -n "$line2" ] && week_pct="$line2"
fi

# Strategy 3: any percentage near "you" / "current" (last resort)
if [ -z "$session_pct" ] && [ -z "$week_pct" ]; then
    any_pct=$(echo "$input" | grep -oE "[0-9]+(\.[0-9]+)?%" | head -1 | tr -d '%')
    [ -n "$any_pct" ] && session_pct="$any_pct"
fi

# Default to null
[ -z "$session_pct" ] && session_pct="null"
[ -z "$week_pct" ] && week_pct="null"

# Force at_limit=true if either pct >= 95
if [ "$session_pct" != "null" ]; then
    if awk -v p="$session_pct" 'BEGIN { exit !(p >= 95) }'; then
        at_limit=true
    fi
fi
if [ "$week_pct" != "null" ]; then
    if awk -v p="$week_pct" 'BEGIN { exit !(p >= 95) }'; then
        at_limit=true
    fi
fi

# Output JSON
printf '{"session_pct": %s, "week_pct": %s, "at_limit": %s, "raw_lines": %d}\n' \
    "$session_pct" "$week_pct" "$at_limit" "$raw_lines"

exit 0
