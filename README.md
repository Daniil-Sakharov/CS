# cs — Claude Code account switcher

Переключение между несколькими аккаунтами Claude Code **без выхода из текущей беседы**. Работает через tmux: один процесс claude убивается и заменяется другим в том же окне, разговор продолжается через `--resume`.

## Что умеет

- `cs <name>` — запустить Claude под аккаунтом в новом tmux-окне
- `cs switch <name>` — переключить аккаунт **внутри живой сессии Claude**, продолжить ту же беседу
- `/work`, `/personal`, `/<любой_аккаунт>` — те же переключения как слэш-команды прямо в Claude
- `/cs <subcommand>` — все админ-команды доступны прямо в Claude
- `cs add/rm/rename/ls/current/doctor/set-color`

История сессий, задачи, file-history, плейны — общие между аккаунтами (через симлинки на `claude-shared/`). Поэтому `/resume` показывает все сессии независимо от того, под каким аккаунтом ты залогинен.

## Установка

```bash
curl -fsSL https://raw.githubusercontent.com/Daniil-Sakharov/CS/main/install.sh | bash
```

Установщик:
1. Проверяет ОС (macOS / Linux).
2. Ставит **tmux** и **jq** через нативный пакетный менеджер (brew / apt-get / dnf / pacman / apk / zypper) если их нет. Без tmux установка падает — главная фича `cs switch` без него не работает.
3. Кладёт файлы в `~/.local/bin/cs` и `~/.local/share/claude-shared/`.
4. Добавляет `fpath` в `~/.zshrc` для tab-completion (zsh).
5. Если есть `~/.claude/statusline-command.sh` — патчит его, чтобы добавить бейдж текущего аккаунта.
6. Запускает `cs doctor`.

После установки перезапусти терминал (или `exec zsh`) и выполни `cs add <name>` чтобы создать первый аккаунт.

## Зависимости

- **tmux** — обязательно
- **jq** — обязательно
- **bash 3+** — на macOS системный (3.2) подходит, GNU bash 4+ тоже работает
- **zsh** — для tab-completion (необязательно, в bash тоже запускается, но без autocomplete)

## Если у тебя уже есть Claude-история

Большинство пользователей запускали Claude по умолчанию (без `CLAUDE_CONFIG_DIR`) — тогда вся история хранится в `~/.claude/`. **Установщик автоматически детектит это** и предлагает импорт. Если согласишься — старая история станет первым cs-аккаунтом и будет видна через `/resume`.

Можно сделать импорт и вручную:

```bash
cs import                           # импортирует ~/.claude/ как аккаунт 'default'
cs import ~/.claude as work         # под другим именем
cs import ~/.claude as work --move  # переносит сессии в shared (компактнее, но необратимо)
```

**Режимы:**
- `--copy` (по умолчанию) — копирует. Оригинал `~/.claude/` остаётся нетронутым. Безопасно для отката.
- `--move` — переносит `projects/`, `sessions/`, `tasks/`, `file-history/`, `plans/`, `history.jsonl` в `claude-shared/`. В исходнике остаются симлинки на shared. Без дублирования.

**Что копируется в новый аккаунт (per-account):** `.claude.json` (OAuth-токены), `settings.json`, `plugins/`, `cache/`, `stats-cache.json`, telemetry, etc.

**Что переносится в shared (общее между аккаунтами):** `projects/`, `sessions/`, `tasks/`, `file-history/`, `plans/`, `history.jsonl`.

## Использование

### Запуск аккаунтов

```bash
cs work                       # открыть Claude как work
cs personal                   # открыть Claude как personal
cs work --continue            # продолжить последнюю сессию work
cs work <session-uuid>        # автоматически делает --resume <uuid>
```

### Переключение внутри Claude

Внутри Claude или внутри tmux:

```bash
cs switch work                # перезапустит окно с work, продолжит ту же беседу
```

То же самое как слэш-команда:

```
/work
/personal
```

### Управление

```bash
cs ls                         # список аккаунтов
cs current                    # активный
cs add foo                    # создать (вне tmux сразу запустит cs foo для логина)
cs add foo --copy-from work   # создать с настройками от work (без OAuth)
cs import [src] [as name]     # импорт существующего ~/.claude/ или другого CCD
cs rm foo                     # удалить (архивирует в .removed-<ts>)
cs rm foo -y                  # без подтверждения
cs rename old new             # переименовать
cs set-color foo magenta      # цвет окна (red/green/yellow/blue/magenta/cyan)
cs doctor                     # проверить зависимости и состояние
```

### Слэш-команды в Claude

```
/cs ls
/cs current
/cs add <name>
/cs rm <name> -y
/cs rename <old> <new>
/cs set-color <name> <color>
/cs doctor
/cs help
/<name>          # переключение на этот аккаунт (генерируется автоматически)
/account         # = /cs current
/accounts        # = /cs ls
```

## Как это работает

```
┌─ tmux окно ──────────────────────────────┐
│  claude (CLAUDE_CONFIG_DIR=claude-work)  │
└──────────────────────────────────────────┘
                   ↓ /work
┌─ tmux окно ──────────────────────────────┐
│  claude (CLAUDE_CONFIG_DIR=claude-pers)  │
│  --resume <session-id>  ← беседа та же   │
└──────────────────────────────────────────┘
```

1. **SessionStart hook** при каждом старте Claude пишет `session_id` в `~/.local/share/claude-shared/tmux-switch/<socket>`.
2. `/work` (или `cs switch work`) читает этот id и вызывает `tmux respawn-window -k`, заменяя процесс на claude с другим `CLAUDE_CONFIG_DIR` и `--resume <id>`.
3. tmux держит окно живым во время замены — визуально пользователь видит ту же беседу через ~1 секунду.

### Что общее, что нет

| Расшарено (общая папка `claude-shared/`) | Per-account |
|---|---|
| `projects/`, `sessions/` (история бесед) | `.claude.json` (OAuth-токены) |
| `history.jsonl` (промпт-история ↑) | `settings.json` |
| `tasks/` (задачи) | `plugins/`, `cache/` |
| `file-history/` (изменённые файлы) | `stats-cache.json`, `telemetry/` |
| `plans/` | `mcp-needs-auth-cache.json` |
| `commands/` (слэш-команды) | `shell-snapshots/` |

## Удаление

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Daniil-Sakharov/CS/main/uninstall.sh)
```

Или из клона: `./uninstall.sh`.

Аккаунты пользователя (с OAuth-токенами и историей) **не удаляются** — это ценные данные. Чтобы снести и их: `rm -rf ~/.local/share/claude-*`.

## Лицензия

MIT
