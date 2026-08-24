#!/usr/bin/env bash
set -euo pipefail

mode_flag="${1:-}"

if [[ "$mode_flag" != "dark" && "$mode_flag" != "light" ]]; then
    if command -v gsettings >/dev/null 2>&1; then
        if [[ "$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null)" == *dark* ]]; then
            mode_flag="dark"
        else
            mode_flag="light"
        fi
    else
        exit 0
    fi
fi

patch_json() {
    local path="$1"
    [ -f "$path" ] || return 0
    if jq -e 'type == "object" and has("theme")' "$path" >/dev/null 2>&1; then
        tmp="$(mktemp)"
        if jq --arg mode "$mode_flag" '.theme = $mode' "$path" > "$tmp"; then
            mv "$tmp" "$path"
        else
            rm -f "$tmp"
        fi
    elif grep -q '"theme"' "$path"; then
        sed -i -E "s/(\"theme\"[[:space:]]*:[[:space:]]*\")[^\"]*(\")/\1${mode_flag}\2/" "$path"
    fi
}

patch_toml() {
    local path="$1"
    [ -f "$path" ] || return 0
    if grep -qE '^theme[[:space:]]*=' "$path"; then
        sed -i -E "s/^(theme[[:space:]]*=[[:space:]]*\")[^\"]*(\")/\1${mode_flag}\2/" "$path"
    fi
}

for f in \
    "${XDG_CONFIG_HOME:-$HOME/.config}/claude/settings.json" \
    "${HOME}/.claude/settings.json"; do
    [ -f "$f" ] && patch_json "$f" && break
done

for f in \
    "${XDG_CONFIG_HOME:-$HOME/.config}/codex/config.toml" \
    "${HOME}/.codex/config.toml"; do
    [ -f "$f" ] && patch_toml "$f" && break
done

for f in \
    "${XDG_CONFIG_HOME:-$HOME/.config}/pi/settings.json" \
    "${HOME}/.pi/agent/settings.json" \
    "${HOME}/.pi/settings.json"; do
    [ -f "$f" ] && patch_json "$f" && break
done
