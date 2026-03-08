# task-inbox.sh

A keyboard-driven script for capturing tasks directly into an [Obsidian](https://obsidian.md/) vault inbox using [rofi](https://github.com/davatorium/rofi), with automatic git push to all configured remotes.

Built for **Arch Linux + Hyprland**, with native theming support for [Omarchy](https://omarchy.org/).

---

## How it works

Press your keybind → two rofi prompts appear in sequence:

1. **Task text** — type what you need to do, hit Enter
2. **Priority** — pick from High ⏫, Medium 🔼, Low 🔽, or None

Escape at either prompt cancels cleanly — nothing is written to disk. Once both are confirmed, the task is appended to `tasks/inbox.md` in your vault using the [Obsidian Tasks](https://publish.obsidian.md/tasks/) plugin format, then committed and pushed to all git remotes synchronously.

**Output format:**
```
- [ ] buy oat milk ⏫
- [ ] reply to email 🔼
- [ ] clean desk
```

---

## Requirements

| Dependency | Purpose |
|---|---|
| `rofi` | prompt UI (dmenu mode) |
| `git` | commit and push vault |
| `util-linux` (`flock`) | atomic file writes |
| `libnotify` (`notify-send`) | success/error notifications |

Install on Arch:
```bash
sudo pacman -S rofi util-linux libnotify
```

---

## Installation

```bash
# 1. Copy the script
cp task-inbox.sh ~/scripts/task-inbox.sh
chmod +x ~/scripts/task-inbox.sh
```

### Vault path

The script assumes your vault is at `~/Documents/Obsidian Vault/` and your inbox at `tasks/inbox.md` inside it. Edit the constants at the top of the script if yours differs:

```bash
readonly VAULT_DIR="${HOME}/Documents/Obsidian Vault"
readonly INBOX_FILE="${VAULT_DIR}/tasks/inbox.md"
```

### Hyprland keybind

Add to `~/.config/hypr/bindings.conf`:

```ini
bind = SUPER, N, exec, ~/scripts/task-inbox.sh
```

Then reload Hyprland or re-source your config.

---

## Omarchy theme integration

If you're on [Omarchy](https://omarchy.org/), the rofi prompt automatically reads your active theme from:

```
~/.config/omarchy/current/theme/colors.toml
```

This path is a symlink that `omarchy-theme-set` updates when you switch themes — so the script always picks up the current theme with no manual configuration. The generated `.rasi` is written to `/tmp` on each run and cleaned up on exit.

If the theme file is absent (non-Omarchy system), it falls back to **Catppuccin Mocha**.

---

## Logging

All errors are written to `/tmp/task-inbox.log`. Useful when debugging keybind-launched failures that produce no terminal output:

```bash
cat /tmp/task-inbox.log
```

---

## Non-Omarchy usage

The script works on any Linux system with rofi. Without Omarchy, it uses Catppuccin Mocha colors by default. To hardcode your own colors, edit the defaults at the top of `generate_rofi_rasi()`:

```bash
local bg="#1e1e2e"
local fg="#cdd6f4"
local accent="#89b4fa"
local sel_bg="#f5e0dc"
local sel_fg="#1e1e2e"
```

---

## Git behaviour

- Stages only `inbox.md` plus any already-tracked modified files (`git add -u`) — will not accidentally stage untracked vault files
- Pushes to **every configured remote** explicitly — if you have both GitHub and Codeberg as remotes, both get pushed
- On partial failure (one remote down), the task is still committed locally and you get a notification identifying which remote failed

---

## License

MIT
