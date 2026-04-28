# cs account badge for Claude Code statusline.
# Вставляется в существующий ~/.claude/statusline-command.sh установщиком.
# Опирается на переменную окружения CLAUDE_CONFIG_DIR, которую Claude Code
# наследует подпроцессам.

cs_account=""
cs_color=""
if [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then
  cs_account=$(basename "$CLAUDE_CONFIG_DIR" | sed 's/^claude-//')
  if [ -f "$CLAUDE_CONFIG_DIR/cs-color" ]; then
    cs_color=$(cat "$CLAUDE_CONFIG_DIR/cs-color")
  fi
  if [ -z "$cs_color" ]; then
    case "$cs_account" in
      personal) cs_color=cyan;;
      work)     cs_color=red;;
      *)        cs_color=blue;;
    esac
  fi
fi

if [ -n "$cs_account" ]; then
  case "$cs_color" in
    red)     bg="41";;
    green)   bg="42";;
    yellow)  bg="43";;
    blue)    bg="44";;
    magenta) bg="45";;
    cyan)    bg="46";;
    *)       bg="40";;
  esac
  printf "\033[${bg};30;1m %s \033[0m " "$cs_account"
fi
