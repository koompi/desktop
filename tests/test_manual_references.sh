#!/usr/bin/env bash
# Every keybind and every koompi command docs/manual/ names must exist in this
# tree. A manual that documents a feature we do not ship is worse than no
# manual, so this test is the thing that stops one being written.
#
# Chords are checked against the bind modules. Most binds are literal strings
# and are read straight out of them. A handful are produced by a loop
# ("SUPER + " .. arrowkey[i]) and cannot be grepped for as text, so each of
# those families is declared below together with the loop that generates it;
# the loop has to still be there or the family is rejected.
#
# Commands are checked against the CLI's own command list, the helper scripts
# in dots/.local/bin, and the packages in sdata/dist-arch.
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
MANUAL="$ROOT/docs/manual"
BIN="$ROOT/dots/.local/bin"
PKGS="$ROOT/sdata/dist-arch"
CLI="$ROOT/cli/src/main.zig"
BIND_MODULES=(
    "$ROOT/dots/.config/hypr/hyprland/keybinds.lua"
    "$ROOT/dots/.config/hypr/hyprland/keybinds_shell_extra.lua"
    "$ROOT/dots/.config/hypr/custom/keybinds.lua"
)

failed=0
pass() { printf 'PASS %s\n' "$*"; }
bad()  { failed=1; printf 'FAIL %s\n' "$*" >&2; }

[[ -d "$MANUAL" ]] || { echo "no docs/manual to check" >&2; exit 1; }
for f in "${BIND_MODULES[@]}" "$CLI"; do
    [[ -f "$f" ]] || { echo "missing source of truth: $f" >&2; exit 1; }
done

# --- canonical chord form ---------------------------------------------------
# Upper-case, punctuation spelled the way Hyprland spells it, modifiers sorted,
# so "Super+Shift+/" and "SHIFT + SUPER + Slash" become the same string.
canon() {
    local raw="${1//[[:space:]]/}" part key="" out=""
    local -a mods=() parts=()
    [[ "$raw" == "+"* || "$raw" == *"+" ]] && { printf '%s' "$raw"; return; }
    local IFS='+'
    # shellcheck disable=SC2206  # deliberate word-split on '+'
    parts=($raw)
    IFS=' '
    for part in "${parts[@]}"; do
        part="${part^^}"
        case "$part" in
            WIN|META|CMD|SUPER) mods+=("SUPER"); continue ;;
            CONTROL|CTRL)       mods+=("CTRL"); continue ;;
            SHIFT)              mods+=("SHIFT"); continue ;;
            ALT)                mods+=("ALT"); continue ;;
        esac
        case "$part" in
            "/")  part="SLASH" ;;
            ",")  part="COMMA" ;;
            ".")  part="PERIOD" ;;
            ";")  part="SEMICOLON" ;;
            "'")  part="APOSTROPHE" ;;
            "\\") part="BACKSLASH" ;;
            '`')  part="GRAVE" ;;
            "-")  part="MINUS" ;;
            "=")  part="EQUAL" ;;
            "[")  part="BRACKETLEFT" ;;
            "]")  part="BRACKETRIGHT" ;;
            PAGEUP)   part="PAGE_UP" ;;
            PAGEDOWN) part="PAGE_DOWN" ;;
            ESC)      part="ESCAPE" ;;
            ENTER)    part="RETURN" ;;
            DEL)      part="DELETE" ;;
        esac
        key="$part"
    done
    # A bare Super is Search, which the config binds as "SUPER + SUPER_L".
    [[ -z "$key" && ${#mods[@]} -eq 1 && ${mods[0]} == "SUPER" ]] && key="SUPER_L"
    (( ${#mods[@]} )) && out="$(printf '%s\n' "${mods[@]}" | LC_ALL=C sort -u | tr '\n' '+')"
    printf '%s%s' "$out" "$key"
}

# --- what the bind modules actually bind ------------------------------------
BOUND="$(mktemp)"; GENERATED="$(mktemp)"; trap 'rm -f "$BOUND" "$GENERATED"' EXIT

grep -ho 'hl\.bind("[^"]*"' "${BIND_MODULES[@]}" \
    | sed 's/^hl\.bind("//; s/"$//' \
    | while IFS= read -r chord; do canon "$chord"; echo; done \
    | LC_ALL=C sort -u > "$BOUND"

bound_count=$(wc -l < "$BOUND")
if (( bound_count < 50 )); then
    bad "only $bound_count literal binds parsed out of the bind modules; the parser is broken"
else
    pass "$bound_count literal chords read from $(basename "${BIND_MODULES[0]}") and its siblings"
fi

# --- chords a loop generates ------------------------------------------------
# "<space-separated chords>|<the loop text that must still be present>"
loop_families=(
    "Super+1 Super+2 Super+3 Super+4 Super+5 Super+6 Super+7 Super+8 Super+9 Super+0|hl.bind(\"SUPER + \" .. (i % 10)"
    "Super+Alt+1 Super+Alt+2 Super+Alt+3 Super+Alt+4 Super+Alt+5 Super+Alt+6 Super+Alt+7 Super+Alt+8 Super+Alt+9 Super+Alt+0|hl.bind(\"SUPER + ALT + \" .. (i % 10)"
    "Super+Left Super+Right Super+Up Super+Down|hl.bind(\"SUPER + \" .. arrowkey[i]"
    "Super+Shift+Left Super+Shift+Right Super+Shift+Up Super+Shift+Down|hl.bind(\"SUPER + SHIFT + \" .. arrowkey[i]"
    "Ctrl+Super+Left Ctrl+Super+Right|hl.bind(\"CTRL + SUPER + \" .. keys[i]"
    "Super+PageUp Super+PageDown|local key = { \"SUPER + Page_Down\", \"SUPER + Page_Up\" }"
    "Super+Shift+PageUp Super+Shift+PageDown|hl.bind(\"SUPER + SHIFT + Page_\" .. keydirs[i]"
    "Super+Ctrl+1 Super+Ctrl+2 Super+Ctrl+3 Super+Ctrl+4|hl.bind(\"SUPER + CTRL + \" .. n,"
)
for family in "${loop_families[@]}"; do
    chords="${family%%|*}"
    snippet="${family#*|}"
    if grep -qF -- "$snippet" "${BIND_MODULES[@]}"; then
        for chord in $chords; do canon "$chord"; echo; done >> "$GENERATED"
    else
        bad "the loop that generates [$chords] is gone: no bind module contains $snippet"
    fi
done
LC_ALL=C sort -u -o "$GENERATED" "$GENERATED"
pass "$(wc -l < "$GENERATED") loop-generated chords, each with its loop still in place"

# --- chords the manual names ------------------------------------------------
# Only inside backticks: prose must not be able to invent a keybind by accident.
chords_in_manual() {
    local code_span="\`[^\`]\\+\`"
    grep -ho "$code_span" "$MANUAL"/*.md \
        | tr -d '`' \
        | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' \
        | grep -E '^(Super|Ctrl|Alt|Shift)(\+[^[:space:]+]+)+$|^(Super|Print)$|^Shift\+Print$' \
        | LC_ALL=C sort -u
}

chord_total=0 chord_bad=0
while IFS= read -r chord; do
    [[ -n "$chord" ]] || continue
    chord_total=$((chord_total + 1))
    c="$(canon "$chord")"
    if ! grep -qxF -- "$c" "$BOUND" && ! grep -qxF -- "$c" "$GENERATED"; then
        bad "keybind '$chord' ($c) is in the manual but bound nowhere"
        chord_bad=$((chord_bad + 1))
    fi
done < <(chords_in_manual)

if (( chord_total == 0 )); then
    bad "no keybinds found in the manual at all; the extractor is broken"
elif (( chord_bad == 0 )); then
    pass "every keybind named in the manual is bound ($chord_total checked)"
fi

# --- koompi subcommands -----------------------------------------------------
cli_commands="$(grep -o 'const command_names = "[^"]*"' "$CLI" | sed 's/.*= "//; s/"$//')"
[[ -n "$cli_commands" ]] || { echo "could not read command_names from $CLI" >&2; exit 1; }

sub_total=0 sub_bad=0
while IFS= read -r sub; do
    [[ -n "$sub" ]] || continue
    sub_total=$((sub_total + 1))
    if ! grep -qw -- "$sub" <<< "$cli_commands"; then
        bad "'koompi $sub' is in the manual but is not a koompi subcommand"
        sub_bad=$((sub_bad + 1))
    fi
done < <(grep -hoE '\bkoompi [a-z][a-z-]*' "$MANUAL"/*.md | awk '{print $2}' | LC_ALL=C sort -u)

if (( sub_total == 0 )); then
    bad "no 'koompi <command>' found in the manual at all; the extractor is broken"
elif (( sub_bad == 0 )); then
    pass "every koompi subcommand named in the manual is in the CLI ($sub_total checked)"
fi

# --- koompi-* names ---------------------------------------------------------
helper_total=0 helper_bad=0
while IFS= read -r helper; do
    [[ -n "$helper" ]] || continue
    helper_total=$((helper_total + 1))
    if [[ ! -e "$BIN/$helper" && ! -d "$PKGS/$helper" ]]; then
        bad "'$helper' is in the manual but is neither in dots/.local/bin nor a package in sdata/dist-arch"
        helper_bad=$((helper_bad + 1))
    fi
done < <(grep -hoE '\bkoompi-[a-z0-9-]+' "$MANUAL"/*.md | LC_ALL=C sort -u)

if (( helper_bad == 0 )); then
    pass "every koompi-* name in the manual exists ($helper_total checked)"
fi

# --- chapter budget ---------------------------------------------------------
chapters=$(find "$MANUAL" -maxdepth 1 -name '[0-9][0-9]-*.md' | wc -l)
if (( chapters > 12 )); then
    bad "$chapters chapters; the manual is capped at 12"
else
    pass "$chapters chapters, within the cap of 12"
fi

long=0
while IFS= read -r file; do
    lines=$(wc -l < "$file")
    if (( lines > 150 )); then
        bad "$(basename "$file") is $lines lines; the cap is 150"
        long=1
    fi
done < <(find "$MANUAL" -maxdepth 1 -name '*.md')
(( long )) || pass "every chapter is 150 lines or fewer"

exit "$failed"
