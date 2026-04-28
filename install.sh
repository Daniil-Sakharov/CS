#!/usr/bin/env bash
# cs installer
# Использование:
#   curl -fsSL https://raw.githubusercontent.com/Daniil-Sakharov/CS/main/install.sh | bash
#   или из клона: ./install.sh
#
# Что делает:
#   1. Проверяет ОС (macOS / Linux), bash 3+, jq.
#   2. Если tmux не установлен — пытается поставить через brew/apt/dnf/pacman/apk.
#   3. Если tmux так и не установлен — fail (без него cs switch теряет смысл).
#   4. Скачивает (или копирует из локального клона) cs/, lib/, templates/.
#   5. Раскладывает файлы:
#        ~/.local/bin/cs
#        ~/.local/share/claude-shared/hooks/session-start.sh
#        ~/.local/share/claude-shared/settings.template.json
#        ~/.local/share/claude-shared/completions/_cs
#        ~/.claude/commands/{cs,account,accounts}.md
#   6. Добавляет fpath в ~/.zshrc и патчит ~/.claude/statusline-command.sh
#      (если он существует) для отображения бейджа аккаунта.
#   7. Запускает cs doctor.

set -eu

REPO="Daniil-Sakharov/CS"
BRANCH="main"
TARBALL_URL="https://github.com/${REPO}/archive/refs/heads/${BRANCH}.tar.gz"

if [ -t 1 ]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
  C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'
  C_CYAN=$'\033[36m'
else
  C_RESET=""; C_BOLD=""; C_DIM=""
  C_RED=""; C_GREEN=""; C_YELLOW=""; C_CYAN=""
fi

say()  { echo "${C_CYAN}==>${C_RESET} $*"; }
warn() { echo "${C_YELLOW}!${C_RESET} $*" >&2; }
err()  { echo "${C_RED}✗${C_RESET} $*" >&2; }
die()  { err "$*"; exit 1; }
ok()   { echo "  ${C_GREEN}✓${C_RESET} $*"; }

# ─── 1. detect environment ────────────────────────────────────────────────────

OS=""
case "$(uname -s)" in
  Darwin) OS=macos ;;
  Linux)  OS=linux ;;
  *)      die "неподдерживаемая ОС: $(uname -s). cs работает на macOS и Linux." ;;
esac

case "$(uname -m)" in
  x86_64|amd64|arm64|aarch64) ;;
  *) warn "необычная архитектура $(uname -m), может работать криво" ;;
esac

if [ -z "${BASH_VERSION:-}" ]; then
  die "запусти через bash"
fi

PKG_MANAGER=""
detect_pkg_manager() {
  if [ "$OS" = "macos" ]; then
    if command -v brew >/dev/null 2>&1; then PKG_MANAGER=brew; fi
  else
    for m in apt-get dnf yum pacman apk zypper; do
      if command -v "$m" >/dev/null 2>&1; then PKG_MANAGER="$m"; return; fi
    done
  fi
}
detect_pkg_manager

install_pkg() {
  local pkg="$1"
  case "$PKG_MANAGER" in
    brew)     brew install "$pkg" ;;
    apt-get)  sudo apt-get update -qq && sudo apt-get install -y "$pkg" ;;
    dnf)      sudo dnf install -y "$pkg" ;;
    yum)      sudo yum install -y "$pkg" ;;
    pacman)   sudo pacman -S --noconfirm "$pkg" ;;
    apk)      sudo apk add --no-cache "$pkg" ;;
    zypper)   sudo zypper install -y "$pkg" ;;
    *)        return 1 ;;
  esac
}

ensure_tool() {
  local tool="$1" pkg="${2:-$1}"
  if command -v "$tool" >/dev/null 2>&1; then
    ok "$tool"
    return 0
  fi
  warn "$tool не установлен"
  if [ -z "$PKG_MANAGER" ]; then
    if [ "$OS" = "macos" ]; then
      err "для установки $tool нужен Homebrew."
      err "поставь Homebrew: https://brew.sh, потом запусти install.sh снова."
    else
      err "пакетный менеджер не найден. установи $tool вручную и запусти install.sh снова."
    fi
    return 1
  fi
  say "ставлю $tool через $PKG_MANAGER..."
  if install_pkg "$pkg"; then
    ok "$tool установлен"
    return 0
  else
    err "не удалось установить $tool автоматически"
    err "поставь $tool вручную и запусти install.sh снова"
    return 1
  fi
}

# ─── 2. dependencies ──────────────────────────────────────────────────────────

say "проверяю зависимости"

ensure_tool tmux || die "tmux обязателен для cs (главная фича — переключение в живой сессии)"
ensure_tool jq   || die "jq обязателен (используется для парсинга settings.json)"
ensure_tool git  || true
ensure_tool curl || ensure_tool wget || die "нужен curl или wget для скачивания файлов"

# ─── 3. fetch sources ─────────────────────────────────────────────────────────

SCRIPT_DIR=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

WORK_DIR=""
cleanup() {
  [ -n "$WORK_DIR" ] && [ -d "$WORK_DIR" ] && rm -rf "$WORK_DIR"
}
trap cleanup EXIT

# Если запущены из клона репо (есть bin/cs рядом), используем локальные файлы.
# Иначе скачиваем tarball.
SRC_DIR=""
if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/bin/cs" ]; then
  say "использую локальные файлы из $SCRIPT_DIR"
  SRC_DIR="$SCRIPT_DIR"
else
  say "скачиваю свежие файлы с GitHub"
  WORK_DIR="$(mktemp -d)"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$TARBALL_URL" | tar -xz -C "$WORK_DIR"
  else
    wget -qO- "$TARBALL_URL" | tar -xz -C "$WORK_DIR"
  fi
  # Tarball содержит каталог CS-<branch>/
  SRC_DIR="$(find "$WORK_DIR" -maxdepth 1 -type d -name 'CS-*' | head -1)"
  [ -d "$SRC_DIR" ] || die "не нашёл распакованный каталог в $WORK_DIR"
fi

# ─── 4. install files ─────────────────────────────────────────────────────────

BIN_DIR="$HOME/.local/bin"
SHARED_DIR="$HOME/.local/share/claude-shared"
HOOKS_DIR="$SHARED_DIR/hooks"
COMP_DIR="$SHARED_DIR/completions"
COMMANDS_DIR="$HOME/.claude/commands"

CS_BIN="$BIN_DIR/cs"
HOOK_SCRIPT="$HOOKS_DIR/session-start.sh"
SETTINGS_TEMPLATE="$SHARED_DIR/settings.template.json"

say "копирую файлы"

mkdir -p "$BIN_DIR" "$HOOKS_DIR" "$COMP_DIR" "$SHARED_DIR" "$COMMANDS_DIR" "$SHARED_DIR/tmux-switch"

cp "$SRC_DIR/bin/cs" "$CS_BIN"
chmod +x "$CS_BIN"
ok "$CS_BIN"

cp "$SRC_DIR/lib/hooks/session-start.sh" "$HOOK_SCRIPT"
chmod +x "$HOOK_SCRIPT"
ok "$HOOK_SCRIPT"

cp "$SRC_DIR/lib/completions/_cs" "$COMP_DIR/_cs"
ok "$COMP_DIR/_cs"

# Подменяем __HOOK_PATH__ в шаблоне на реальный путь к hook.
sed "s|__HOOK_PATH__|$HOOK_SCRIPT|g" "$SRC_DIR/lib/templates/settings.template.json" > "$SETTINGS_TEMPLATE"
ok "$SETTINGS_TEMPLATE"

# ─── 5. shell integration ─────────────────────────────────────────────────────

ensure_line_in_file() {
  local line="$1" file="$2"
  [ -f "$file" ] || touch "$file"
  if ! grep -qxF "$line" "$file"; then
    printf '\n%s\n' "$line" >> "$file"
    return 0
  fi
  return 1
}

say "интеграция с shell"

# Проверяем что ~/.local/bin в PATH
case ":${PATH}:" in
  *":$BIN_DIR:"*) ok "$BIN_DIR в PATH" ;;
  *)
    if [ -f "$HOME/.zshrc" ]; then
      ensure_line_in_file 'export PATH="$HOME/.local/bin:$PATH"' "$HOME/.zshrc" \
        && ok "$BIN_DIR добавлен в PATH через ~/.zshrc" \
        || ok "PATH уже настроен"
    fi
    if [ -f "$HOME/.bashrc" ]; then
      ensure_line_in_file 'export PATH="$HOME/.local/bin:$PATH"' "$HOME/.bashrc" >/dev/null || true
    fi
    ;;
esac

# zsh completion: fpath ДО oh-my-zsh / compinit
ZSH_FPATH_LINE='fpath=("$HOME/.local/share/claude-shared/completions" $fpath)'
if [ -f "$HOME/.zshrc" ]; then
  if grep -qF 'claude-shared/completions' "$HOME/.zshrc" 2>/dev/null; then
    ok "fpath уже в ~/.zshrc"
  else
    # Найдём строку с oh-my-zsh source / compinit и вставим до неё
    if grep -qE '^(source.*oh-my-zsh\.sh|autoload.*compinit|compinit)' "$HOME/.zshrc"; then
      tmpfile="$(mktemp)"
      awk -v line="$ZSH_FPATH_LINE" '
        /^(source.*oh-my-zsh\.sh|autoload.*compinit|^compinit)/ && !done {
          print "# cs completions"
          print line
          print ""
          done = 1
        }
        { print }
      ' "$HOME/.zshrc" > "$tmpfile" && mv "$tmpfile" "$HOME/.zshrc"
    else
      printf '\n# cs completions\n%s\n' "$ZSH_FPATH_LINE" >> "$HOME/.zshrc"
    fi
    ok "fpath добавлен в ~/.zshrc"
  fi
fi

# Statusline-бейдж: патчим существующий ~/.claude/statusline-command.sh
STATUSLINE="$HOME/.claude/statusline-command.sh"
if [ -f "$STATUSLINE" ]; then
  if grep -qF 'cs_account=' "$STATUSLINE" 2>/dev/null; then
    ok "statusline уже патчен"
  else
    say "патчу $STATUSLINE — добавляю бейдж аккаунта"
    cp "$STATUSLINE" "$STATUSLINE.bak.$(date +%s)"
    snippet="$(cat "$SRC_DIR/lib/templates/statusline-snippet.sh")"
    # Вставляем snippet после первого `input=$(cat)`
    if grep -qE '^input=\$\(cat\)' "$STATUSLINE"; then
      tmpfile="$(mktemp)"
      awk -v snip="$snippet" '
        /^input=\$\(cat\)/ && !done {
          print
          print ""
          print snip
          done = 1
          next
        }
        { print }
      ' "$STATUSLINE" > "$tmpfile" && mv "$tmpfile" "$STATUSLINE"
      # Перед первым printf добавляем вывод бейджа (если еще не было)
      if ! grep -qE 'printf.*cs_account|\$\{bg\}' "$STATUSLINE"; then
        warn "не смог автоматически вставить вывод бейджа в printf"
        warn "ручная правка: добавь до первой printf:"
        warn '  if [ -n "$cs_account" ]; then ... (см. lib/templates/statusline-snippet.sh)'
      fi
    fi
    ok "statusline пропатчен (бэкап в $STATUSLINE.bak.*)"
  fi
else
  ok "statusline не найден — пропускаю (если появится — запусти install.sh снова)"
fi

# ─── 6. cs doctor ─────────────────────────────────────────────────────────────

say "запускаю cs doctor"
"$CS_BIN" doctor || true

# ─── 7. summary ───────────────────────────────────────────────────────────────

cat <<EOF

${C_GREEN}${C_BOLD}✓ установка завершена${C_RESET}

${C_BOLD}первые шаги:${C_RESET}
  1. Перезагрузи терминал: ${C_CYAN}exec zsh${C_RESET}  (или открой новое окно)
  2. Создай первый аккаунт:  ${C_CYAN}cs add work${C_RESET}
  3. Залогинься:             ${C_CYAN}cs work${C_RESET}      ${C_DIM}# /login внутри Claude${C_RESET}
  4. Из второго терминала:   ${C_CYAN}cs add personal${C_RESET}, потом ${C_CYAN}cs personal${C_RESET}
  5. Внутри Claude:          ${C_CYAN}/personal${C_RESET} или ${C_CYAN}/work${C_RESET} переключают аккаунт без перезапуска

${C_BOLD}справка:${C_RESET}  ${C_CYAN}cs help${C_RESET}
${C_BOLD}проверка:${C_RESET} ${C_CYAN}cs doctor${C_RESET}
${C_BOLD}удаление:${C_RESET} ${C_CYAN}bash <(curl -fsSL https://raw.githubusercontent.com/${REPO}/${BRANCH}/uninstall.sh)${C_RESET}

EOF
