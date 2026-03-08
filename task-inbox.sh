#!/usr/bin/env bash
# =============================================================================
# task-inbox.sh — Append a task to Obsidian vault inbox and push to remotes
#
# Usage: task-inbox.sh
# Dependencies: rofi (dmenu mode), git, flock, notify-send, date
#
# Vault:    ~/Documents/Obsidian Vault/
# Inbox:    ~/Documents/Obsidian Vault/tasks/inbox.md
# Author:   Rubait
# =============================================================================

set -euo pipefail
IFS=$'\n\t'

# ── Constants ─────────────────────────────────────────────────────────────────

readonly VAULT_DIR="${HOME}/Documents/Obsidian Vault"
readonly INBOX_FILE="${VAULT_DIR}/tasks/inbox.md"
readonly LOCK_FILE="/tmp/task-inbox.lock"
readonly LOG_FILE="/tmp/task-inbox.log"
readonly SCRIPT_NAME="$(basename "$0")"

# Omarchy active theme — symlink always points to current theme dir
readonly OMARCHY_COLORS_TOML="${HOME}/.config/omarchy/current/theme/colors.toml"
# Temp .rasi regenerated each run from the active theme; cleaned up on exit
readonly THEME_FILE="/tmp/task-inbox.rasi"

# ── Notification helpers ───────────────────────────────────────────────────────

notify_info()  { notify-send -a "Task Inbox" -i "checkbox-checked" -t 4000 "$1" "${2:-}"; }
notify_error() { notify-send -a "Task Inbox" -i "dialog-error"     -t 6000 "Error" "$1"; }

die() {
    local msg="$1"
    printf '[%s] ERROR: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "${msg}" >> "${LOG_FILE}"
    notify_error "${msg}" || true
    exit 1
}

# ── Omarchy theme integration ─────────────────────────────────────────────────
#
# Reads colors.toml from the active theme (via the symlink omarchy-theme-set
# maintains at ~/.config/omarchy/current/theme). Generates a rofi .rasi file
# matching the current theme. Falls back to Catppuccin Mocha if unavailable.

# Extract a single color key from colors.toml.
# Format is always: key = "#RRGGBB" — no toml parser needed.
_toml_color() {
    local key="$1"
    local file="$2"
    grep -m1 "^${key}[[:space:]]*=" "${file}" \
        | sed 's/.*=[[:space:]]*"\(#[0-9A-Fa-f]*\)".*/\1/'
}

# Hex color -> "R,G,B" triplet for rgba() in rasi
_hex_to_rgb() {
    local hex="${1#\#}"
    printf '%d,%d,%d' \
        "0x${hex:0:2}" \
        "0x${hex:2:2}" \
        "0x${hex:4:2}"
}

generate_rofi_rasi() {
    # ── Defaults (Catppuccin Mocha — safe fallback) ──────────────────────────
    local bg="#1e1e2e"
    local fg="#cdd6f4"
    local accent="#89b4fa"
    local sel_bg="#f5e0dc"
    local sel_fg="#1e1e2e"

    # ── Override from active Omarchy theme if available ───────────────────────
    if [[ -f "${OMARCHY_COLORS_TOML}" ]]; then
        local t_bg t_fg t_accent t_sel_bg t_sel_fg
        t_bg="$(     _toml_color "background"           "${OMARCHY_COLORS_TOML}")"
        t_fg="$(     _toml_color "foreground"           "${OMARCHY_COLORS_TOML}")"
        t_accent="$( _toml_color "accent"               "${OMARCHY_COLORS_TOML}")"
        t_sel_bg="$( _toml_color "selection_background" "${OMARCHY_COLORS_TOML}")"
        t_sel_fg="$( _toml_color "selection_foreground" "${OMARCHY_COLORS_TOML}")"

        [[ "${t_bg}"     =~ ^#[0-9A-Fa-f]{6}$ ]] && bg="${t_bg}"
        [[ "${t_fg}"     =~ ^#[0-9A-Fa-f]{6}$ ]] && fg="${t_fg}"
        [[ "${t_accent}" =~ ^#[0-9A-Fa-f]{6}$ ]] && accent="${t_accent}"
        [[ "${t_sel_bg}" =~ ^#[0-9A-Fa-f]{6}$ ]] && sel_bg="${t_sel_bg}"
        [[ "${t_sel_fg}" =~ ^#[0-9A-Fa-f]{6}$ ]] && sel_fg="${t_sel_fg}"
    fi

    # ── Derive surface — bg blended 10% toward fg (no bc/awk dep) ────────────
    local bg_hex="${bg#\#}"
    local fg_hex="${fg#\#}"
    local r=$(( (16#${bg_hex:0:2} * 90 + 16#${fg_hex:0:2} * 10) / 100 ))
    local g=$(( (16#${bg_hex:2:2} * 90 + 16#${fg_hex:2:2} * 10) / 100 ))
    local b=$(( (16#${bg_hex:4:2} * 90 + 16#${fg_hex:4:2} * 10) / 100 ))
    local surface
    surface="$(printf '#%02x%02x%02x' "${r}" "${g}" "${b}")"

    # ── Write .rasi ───────────────────────────────────────────────────────────
    cat > "${THEME_FILE}" << EOF
* {
    font:             "monospace 13";
    background-color: transparent;
    text-color:       ${fg};
}

window {
    background-color: ${bg};
    border:           2px solid;
    border-color:     ${accent};
    border-radius:    10px;
    width:            580px;
    padding:          8px;
}

mainbox {
    background-color: transparent;
    spacing:          6px;
    children:         [inputbar, listview];
}

inputbar {
    background-color: ${surface};
    border:           1px solid;
    border-color:     rgba($(_hex_to_rgb "${accent}"), 0.4);
    border-radius:    6px;
    padding:          6px 10px;
    spacing:          6px;
    children:         [prompt, entry];
}

prompt {
    background-color: transparent;
    text-color:       ${accent};
    padding:          0px 4px 0px 0px;
}

entry {
    background-color:  transparent;
    text-color:        ${fg};
    placeholder:       "type here...";
    placeholder-color: rgba($(_hex_to_rgb "${fg}"), 0.35);
    cursor:            text;
}

listview {
    background-color: transparent;
    spacing:          2px;
    padding:          4px 0px 0px 0px;
    lines:            5;
    scrollbar:        false;
}

element {
    background-color: transparent;
    text-color:       ${fg};
    padding:          6px 10px;
    border-radius:    6px;
}

element selected {
    background-color: ${sel_bg};
    text-color:       ${sel_fg};
}

element-text {
    background-color: transparent;
    text-color:       inherit;
    highlight:        none;
}
EOF
}

# ── dmenu wrapper ─────────────────────────────────────────────────────────────
#
# Usage: dmenu_prompt <prompt_text> [--free-entry]
#   --free-entry: pure text input, no list items read from stdin.
#
# Returns the selected/typed string on stdout.
# Returns empty string (exit 0) if user cancels — callers must check.

DMENU_BACKEND=""

_detect_dmenu_backend() {
    if command -v rofi &>/dev/null; then
        DMENU_BACKEND="rofi"
    elif command -v wofi &>/dev/null; then
        DMENU_BACKEND="wofi"
    else
        die "No dmenu backend found. Install rofi."
    fi
}

dmenu_prompt() {
    local prompt="$1"
    local free_entry="${2:-}"
    local result=""

    case "${DMENU_BACKEND}" in
        rofi)
            if [[ "${free_entry}" == "--free-entry" ]]; then
                result="$(rofi \
                    -dmenu \
                    -p "${prompt}" \
                    -lines 0 \
                    -theme "${THEME_FILE}" \
                    2>/dev/null || true)"
            else
                result="$(rofi \
                    -dmenu \
                    -p "${prompt}" \
                    -lines 5 \
                    -theme "${THEME_FILE}" \
                    2>/dev/null || true)"
            fi
            ;;
        wofi)
            # Wofi fallback — unstyled, theme file is rasi and incompatible
            if [[ "${free_entry}" == "--free-entry" ]]; then
                result="$(printf '' | wofi \
                    --dmenu \
                    --prompt "${prompt}" \
                    --lines 0 \
                    --width 600 \
                    --hide-scroll \
                    2>/dev/null || true)"
            else
                result="$(wofi \
                    --dmenu \
                    --prompt "${prompt}" \
                    --lines 5 \
                    --width 400 \
                    --hide-scroll \
                    2>/dev/null || true)"
            fi
            ;;
        *)
            die "Unknown dmenu backend: ${DMENU_BACKEND}"
            ;;
    esac

    printf '%s' "${result}"
}

# ── Priority selection ─────────────────────────────────────────────────────────

select_priority() {
    local choice
    choice="$(printf '%s\n' \
        "⏫  High" \
        "🔼  Medium" \
        "🔽  Low" \
        "—   None" \
        | dmenu_prompt "Priority:")"

    case "${choice}" in
        "⏫  High")   printf '⏫'  ;;
        "🔼  Medium") printf '🔼'  ;;
        "🔽  Low")    printf '🔽'  ;;
        "—   None")  printf 'NONE' ;;  # explicit choice — no emoji, but not a cancel
        *)            printf ''    ;;  # empty = Escape / cancelled
    esac
}

# ── File append — atomic via flock ────────────────────────────────────────────

append_task() {
    local task_line="$1"

    (
        flock -x -w 5 200 || die "Could not acquire lock on inbox file."

        [[ -d "$(dirname "${INBOX_FILE}")" ]] \
            || die "Inbox directory does not exist: $(dirname "${INBOX_FILE}")"

        if [[ ! -f "${INBOX_FILE}" ]]; then
            printf '# Inbox\n\n' > "${INBOX_FILE}"
        fi

        if [[ -s "${INBOX_FILE}" ]]; then
            [[ "$(tail -c1 "${INBOX_FILE}"; printf x)" != $'\nx' ]] \
                && printf '\n' >> "${INBOX_FILE}"
        fi

        printf '%s\n' "${task_line}" >> "${INBOX_FILE}"

    ) 200>"${LOCK_FILE}"
}

# ── Git sync ───────────────────────────────────────────────────────────────────

git_sync() {
    local vault_dir="$1"
    local commit_msg="$2"
    local git_errors=""

    # Keybind-launched processes don't inherit SSH_AUTH_SOCK from the terminal
    # session. GNOME Keyring acts as the SSH agent on this system — resolve its
    # socket explicitly so git can authenticate even without a terminal.
    local keyring_sock="/run/user/$(id -u)/keyring/ssh"
    if [[ -S "${keyring_sock}" ]]; then
        export SSH_AUTH_SOCK="${keyring_sock}"
    fi

    pushd "${vault_dir}" > /dev/null

    git add "${INBOX_FILE}"
    git add -u

    if git diff --cached --quiet; then
        popd > /dev/null
        notify_info "Task saved" "Inbox updated (nothing new to commit)."
        return 0
    fi

    git commit -m "${commit_msg}" \
        || { popd > /dev/null; die "git commit failed."; }

    local remotes
    remotes="$(git remote)"
    if [[ -z "${remotes}" ]]; then
        popd > /dev/null
        notify_info "Task saved" "Committed locally — no remotes configured."
        return 0
    fi

    while IFS= read -r remote; do
        if ! git push "${remote}" 2>&1; then
            git_errors="${git_errors}Push to '${remote}' failed.\n"
        fi
    done <<< "${remotes}"

    popd > /dev/null

    if [[ -n "${git_errors}" ]]; then
        notify_error "$(printf '%b' "${git_errors}")Task was saved locally."
        return 1
    fi

    return 0
}

# ── Main ───────────────────────────────────────────────────────────────────────

main() {
    exec 2>>"${LOG_FILE}"

    generate_rofi_rasi
    trap 'rm -f "${THEME_FILE}"' EXIT

    _detect_dmenu_backend

    # ── Step 1: get task text
    local task_text
    task_text="$(dmenu_prompt "New task..." --free-entry)"

    [[ -z "${task_text}" ]] && exit 0

    task_text="$(printf '%s' "${task_text}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [[ -z "${task_text}" ]] && exit 0

    # ── Step 2: select priority
    local priority_emoji
    priority_emoji="$(select_priority)"

    # Empty = Escape pressed — discard the task entirely
    [[ -z "${priority_emoji}" ]] && exit 0

    # NONE = user explicitly chose no priority — clear the sentinel before use
    [[ "${priority_emoji}" == "NONE" ]] && priority_emoji=""

    # ── Step 3: build task line
    local task_line
    if [[ -n "${priority_emoji}" ]]; then
        task_line="- [ ] ${task_text} ${priority_emoji}"
    else
        task_line="- [ ] ${task_text}"
    fi

    # ── Step 4: append to inbox (atomic)
    append_task "${task_line}"

    # ── Step 5: git commit + push (synchronous)
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M')"
    git_sync "${VAULT_DIR}" "add: task via script [${timestamp}]"

    notify_info "Task added ✓" "${task_line}"
}

main "$@"
