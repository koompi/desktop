#!/usr/bin/env bash
# The Super+/ cheatsheet is generated from each bind's `description`, so a bind
# without one is invisible to users (docs/navigation.md). A `-- # [hidden]`
# comment on the statement opts a bind out on purpose; everything else in
# keybinds.lua and custom/keybinds.lua must be described.
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
FILES=(
    "$ROOT/dots/.config/hypr/hyprland/keybinds.lua"
    "$ROOT/dots/.config/hypr/custom/keybinds.lua"
)
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

# One record per hl.bind( statement, which may span lines: the statement ends
# when the parentheses balance outside string literals. Strings and comments
# are stripped before counting so `$(...)` inside an exec_cmd does not count,
# and `description` is looked for as the remaining table key, not as text.
scan() {
    awk '
        function strip(s) {
            gsub(/\\./, "", s)
            gsub(/"[^"]*"/, "", s)
            gsub(/\x27[^\x27]*\x27/, "", s)
            return s
        }
        {
            line = $0
            if (!inbind) {
                if (line ~ /^[ \t]*--/) next
                i = index(line, "hl.bind(")
                if (i == 0) next
                inbind = 1; start = NR; depth = 0; hidden = 0; described = 0
                line = substr(line, i)
            }
            s = strip(line)
            c = index(s, "--")
            if (c > 0) {
                if (substr(s, c) ~ /\[hidden\]/) hidden = 1
                s = substr(s, 1, c - 1)
            }
            if (s ~ /description[ \t]*=/) described = 1
            depth += gsub(/\(/, "(", s) - gsub(/\)/, ")", s)
            if (depth <= 0) {
                printf "%d\t%d\t%d\n", start, described, hidden
                inbind = 0
            }
        }
        END { if (inbind) { print "unterminated hl.bind( starting at line " start > "/dev/stderr"; exit 2 } }
    ' "$1"
}

total=0
missing=0
for file in "${FILES[@]}"; do
    [[ -f "$file" ]] || fail "missing $file"
    records="$(scan "$file")" || fail "could not parse $file"
    while IFS=$'\t' read -r line described hidden; do
        [[ -n "$line" ]] || continue
        total=$((total + 1))
        (( hidden )) && continue
        (( described )) && continue
        missing=$((missing + 1))
        printf '%s:%s: %s\n' "${file#"$ROOT"/}" "$line" "$(sed -n "${line}p" "$file" | sed 's/^[ \t]*//' | cut -c1-110)"
    done <<< "$records"
done

(( total > 100 )) || fail "only $total hl.bind( statements found; the scanner lost the file"
(( missing == 0 )) || fail "$missing of $total binds have no description and are not marked [hidden]"
printf 'keybind descriptions: all %d binds described or hidden\n' "$total"
