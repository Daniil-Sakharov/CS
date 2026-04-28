#!/usr/bin/env bash
# cs uninstaller
# Удаляет программу cs и её shared-инфраструктуру.
# НЕ ТРОГАЕТ:
#   - Пользовательские аккаунты ~/.local/share/claude-<name>/
#     (там OAuth-токены и история сессий — ценные данные).
#   - Сессии Claude Code в claude-shared/{projects,sessions,tasks,...}.
#
# Удаляет:
#   - ~/.local/bin/cs
#   - ~/.local/share/claude-shared/{hooks,completions,settings.template.json,tmux-switch}
#   - ~/.claude/commands/{cs,account,accounts,<account>}.md (только сгенерированные cs)
#   - fpath строку из ~/.zshrc
#
# Использование:
#   bash uninstall.sh
#   bash <(curl -fsSL https://raw.githubusercontent.com/Daniil-Sakharov/CS/main/uninstall.sh)

set -eu

if [ -t 1 ]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'
  C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_CYAN=$'\033[36m'
else
  C_RESET=""; C_BOLD=""
  C_RED=""; C_GREEN=""; C_YELLOW=""; C_CYAN=""
fi

ok()  { echo "  ${C_GREEN}✓${C_RESET} $*"; }
say() { echo "${C_CYAN}==>${C_RESET} $*"; }
warn(){ echo "${C_YELLOW}!${C_RESET} $*"; }

cat <<EOF

${C_BOLD}cs uninstall${C_RESET}

будет удалено:
  - ~/.local/bin/cs
  - ~/.local/share/claude-shared/hooks/session-start.sh
  - ~/.local/share/claude-shared/completions/_cs
  - ~/.local/share/claude-shared/settings.template.json
  - ~/.local/share/claude-shared/tmux-switch/
  - ~/.claude/commands/{cs,account,accounts}.md и сгенерированные /<name>.md
  - fpath cs из ~/.zshrc

${C_BOLD}останется (намеренно):${C_RESET}
  - ~/.local/share/claude-<name>/ (твои аккаунты, OAuth-токены)
  - ~/.local/share/claude-shared/{projects,sessions,history.jsonl,tasks,...} (сессии Claude)

EOF

if [ -t 0 ]; then
  printf "продолжить? (y/N): "
  read -r ans
  case "$ans" in
    y|Y|yes|YES|Yes) ;;
    *) echo "отменено."; exit 0;;
  esac
else
  if [ "${CS_UNINSTALL_YES:-}" != "1" ]; then
    echo "не TTY — установи CS_UNINSTALL_YES=1 для подтверждения"
    exit 1
  fi
fi

CS_BIN="$HOME/.local/bin/cs"
SHARED_DIR="$HOME/.local/share/claude-shared"
COMMANDS_DIR="$HOME/.claude/commands"

# 1. cs binary
[ -f "$CS_BIN" ] && rm -f "$CS_BIN" && ok "удалён $CS_BIN"

# 2. shared infra (но не projects/sessions/tasks/history)
[ -f "$SHARED_DIR/hooks/session-start.sh" ] && rm -f "$SHARED_DIR/hooks/session-start.sh" && ok "удалён hook"
[ -d "$SHARED_DIR/hooks" ] && rmdir "$SHARED_DIR/hooks" 2>/dev/null && ok "удалена hooks/" || true
[ -f "$SHARED_DIR/completions/_cs" ] && rm -f "$SHARED_DIR/completions/_cs" && ok "удалён _cs"
[ -d "$SHARED_DIR/completions" ] && rmdir "$SHARED_DIR/completions" 2>/dev/null && ok "удалена completions/" || true
[ -f "$SHARED_DIR/settings.template.json" ] && rm -f "$SHARED_DIR/settings.template.json" && ok "удалён template"
[ -d "$SHARED_DIR/tmux-switch" ] && rm -rf "$SHARED_DIR/tmux-switch" && ok "удалена tmux-switch/"

# 3. slash commands
if [ -d "$COMMANDS_DIR" ]; then
  rm -f "$COMMANDS_DIR/cs.md" "$COMMANDS_DIR/account.md" "$COMMANDS_DIR/accounts.md"
  shopt -s nullglob
  for f in "$COMMANDS_DIR"/*.md; do
    if grep -q "/.local/bin/cs switch" "$f" 2>/dev/null; then
      rm -f "$f"
      ok "удалена $(basename "$f")"
    fi
  done
  shopt -u nullglob
  ok "слэш-команды cs удалены"
fi

# 4. zshrc fpath
if [ -f "$HOME/.zshrc" ] && grep -qF 'claude-shared/completions' "$HOME/.zshrc"; then
  tmpfile="$(mktemp)"
  grep -vF 'claude-shared/completions' "$HOME/.zshrc" | grep -vxF '# cs completions' > "$tmpfile" && mv "$tmpfile" "$HOME/.zshrc"
  ok "fpath удалён из ~/.zshrc"
fi

# 5. statusline patch
STATUSLINE="$HOME/.claude/statusline-command.sh"
if [ -f "$STATUSLINE" ] && grep -qF 'cs_account=' "$STATUSLINE"; then
  bak="$(ls -1t "$STATUSLINE.bak."* 2>/dev/null | head -1 || true)"
  if [ -n "$bak" ] && [ -f "$bak" ]; then
    cp "$bak" "$STATUSLINE"
    ok "statusline восстановлен из бэкапа $bak"
  else
    warn "statusline пропатчен, но бэкап не найден — поправь руками: $STATUSLINE"
  fi
fi

# 6. account symlinks (commands → ~/.claude/commands)
for d in "$HOME/.local/share/claude-"*/; do
  [ -d "$d" ] || continue
  link="$d/commands"
  if [ -L "$link" ]; then
    rm -f "$link"
  fi
done

cat <<EOF

${C_GREEN}${C_BOLD}✓ cs удалён${C_RESET}

аккаунты сохранены: ~/.local/share/claude-*/
если хочешь удалить и их вручную: ${C_CYAN}rm -rf ~/.local/share/claude-*${C_RESET} ${C_YELLOW}(потеряешь OAuth-токены и историю)${C_RESET}

EOF
