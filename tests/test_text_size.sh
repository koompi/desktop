#!/usr/bin/env bash
# One text-size knob (AUDIT O18). `koompi-theme text-size N` must move the
# shell (appearance.fonts.baseSize in config.json), GTK (text-scaling-factor,
# quantised to a whole GTK point) and the terminal (~/.config/koompi/text-size,
# read by wezterm.lua) together, and 16 must leave all three at the shipped
# values: the Appearance.qml ladder scaled from 16 reproduces today's ten
# sizes exactly, GTK's factor is 1.0 and wezterm's font is 11.5 pt.
#
# gsettings and koompi-hook are shims that record what they were asked; jq and
# the coreutils are real. Everything runs under a throwaway HOME.
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
Q="$ROOT/dots/.config/quickshell/koompi"
THEME="$ROOT/dots/.local/bin/koompi-theme"
WEZTERM="$ROOT/dots/.config/wezterm/wezterm.lua"
APPEARANCE="$Q/modules/common/Appearance.qml"
CONFIG_QML="$Q/modules/common/Config.qml"
FONTS_QML="$Q/modules/settings/interface/FontsSection.qml"
ALLOW="$ROOT/tests/file-length-allow.txt"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq not installed; skipping" >&2; exit 0; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
stub="$tmp/bin"; home="$tmp/home"
mkdir -p "$stub" "$home/.config/koompi"
config="$home/.config/koompi/config.json"
size_file="$home/.config/koompi/text-size"

# gsettings: `get font-name` answers the way a real KOOMPI session does, with
# the variation suffix after the point size, so the size parser is exercised
# on that; `set`/`reset` are recorded and `get text-scaling-factor` replays
# the last one. GTK_FONT_PT lets a case pick another interface font size.
cat > "$stub/gsettings" <<'STUB'
#!/usr/bin/env bash
state="$GSETTINGS_STATE"
case "$1 $3" in
    "get font-name") printf "'Google Sans Flex Medium %s @opsz=11,wght=500'\n" "${GTK_FONT_PT:-11}" ;;
    "get text-scaling-factor") [[ -f "$state" ]] && cat "$state" || echo 1.0 ;;
    "set text-scaling-factor") printf '%s\n' "$4" > "$state"; printf 'set %s %s %s\n' "$2" "$3" "$4" >> "$GSETTINGS_LOG" ;;
    "reset text-scaling-factor") echo 1.0 > "$state"; printf 'reset %s %s\n' "$2" "$3" >> "$GSETTINGS_LOG" ;;
    *) echo "unexpected gsettings $*" >&2; exit 1 ;;
esac
STUB
cat > "$stub/koompi-hook" <<'STUB'
#!/usr/bin/env bash
printf '%s text-size=%s\n' "$1" "${KOOMPI_HOOK_TEXT_SIZE:-unset}" >> "$HOOK_LOG"
STUB
chmod +x "$stub"/*

run_theme() {
    HOME="$home" XDG_CONFIG_HOME="$home/.config" PATH="$stub:$PATH" \
        GSETTINGS_STATE="$tmp/gstate" GSETTINGS_LOG="$tmp/gsettings.log" HOOK_LOG="$tmp/hook.log" \
        bash "$THEME" text-size "$@" > "$tmp/out" 2> "$tmp/err"
}
base_size() { jq -r '.appearance.fonts.baseSize' "$config"; }

# --- 1. the ladder: ten steps scaled from baseSize 16 are today's ten values ---
grep -q 'property int normal: Config.options.appearance.fonts.baseSize' "$APPEARANCE" \
    || fail "Appearance.qml's pixelSize.normal no longer comes from appearance.fonts.baseSize"
grep -qE 'property int baseSize: 16( |$)' "$CONFIG_QML" \
    || fail "Config.qml no longer defaults appearance.fonts.baseSize to 16"
expected="smallest=10 smaller=12 smallie=13 small=15 large=17 larger=19 huge=22 hugeass=23"
got="$(awk 'match($0, /property int ([a-z]+): Math\.round\(normal \* ([0-9.]+)\)/, m) {
        v = 16 * m[2]; printf "%s%s=%d", sep, m[1], int(v + 0.5); sep = " " }' "$APPEARANCE")"
[[ "$got" == "$expected" ]] || fail "ladder at baseSize 16 is '$got', shipped sizes were '$expected'"
grep -q 'property int title: huge' "$APPEARANCE" || fail "pixelSize.title is no longer huge"
echo "ok   ladder: $got, title=huge"

# --- 2. set: config key, quantised GTK factor, terminal half-points, hook ---
echo '{"appearance":{"fonts":{"main":"Google Sans Flex"}},"bar":{"bottom":true}}' > "$config"
chmod 644 "$config"
run_theme 18 || fail "text-size 18 failed: $(cat "$tmp/err")"
[[ "$(base_size)" == 18 ]] || fail "baseSize not written: $(jq -c . "$config")"
[[ "$(jq -r '.appearance.fonts.main, .bar.bottom' "$config" | paste -sd' ')" == "Google Sans Flex true" ]] \
    || fail "other keys did not survive the write: $(jq -c . "$config")"
[[ "$(stat -c %a "$config")" == 644 ]] || fail "config.json mode changed to $(stat -c %a "$config")"
# 11 pt * 18/16 = 12.375 -> 12 pt -> 12/11
[[ "$(tail -n1 "$tmp/gsettings.log")" == "set org.gnome.desktop.interface text-scaling-factor 1.0909" ]] \
    || fail "GTK factor for 18 px: $(tail -n1 "$tmp/gsettings.log")"
# 18 * 11.5/16 = 12.9375 -> nearest half point
[[ "$(cat "$size_file")" == 13.0 ]] || fail "terminal size for 18 px is $(cat "$size_file"), want 13.0"
[[ "$(tail -n1 "$tmp/hook.log")" == "theme-set text-size=18" ]] || fail "hook not fired: $(cat "$tmp/hook.log" 2>&1)"
[[ -z "$(find "$home/.config/koompi" -name 'config.json.*' -o -name 'text-size.*')" ]] \
    || fail "temp files left behind: $(ls "$home/.config/koompi")"
echo "ok   set 18: baseSize=18 gtk=1.0909 terminal=13.0 hook fired"

# --- 3. quantisation: whole GTK points, anchored so 16 px is exactly 1.0 ---
run_theme 20 || fail "text-size 20 failed: $(cat "$tmp/err")"
[[ "$(tail -n1 "$tmp/gsettings.log")" == *" 1.2727" ]] || fail "20 px: $(tail -n1 "$tmp/gsettings.log") (11*20/16=13.75 -> 14/11)"
[[ "$(cat "$size_file")" == 14.5 ]] || fail "20 px terminal: $(cat "$size_file")"
GTK_FONT_PT=10 run_theme 18 || fail "text-size 18 at 10 pt failed"
[[ "$(tail -n1 "$tmp/gsettings.log")" == *" 1.1000" ]] || fail "18 px on a 10 pt font: $(tail -n1 "$tmp/gsettings.log") (10*18/16=11.25 -> 11/10)"
run_theme 9 || fail "text-size 9 failed"
[[ "$(tail -n1 "$tmp/gsettings.log")" == *" 0.5455" && "$(cat "$size_file")" == 6.5 ]] \
    || fail "9 px: $(tail -n1 "$tmp/gsettings.log") / $(cat "$size_file")"
run_theme 24 || fail "text-size 24 failed"
[[ "$(tail -n1 "$tmp/gsettings.log")" == *" 1.5455" && "$(cat "$size_file")" == 17.5 ]] \
    || fail "24 px: $(tail -n1 "$tmp/gsettings.log") / $(cat "$size_file")"
echo "ok   quantised: 20->1.2727/14.5, 18@10pt->1.1000, 9->0.5455/6.5, 24->1.5455/17.5"

# --- 4. reset: 16 everywhere, GTK back to the schema default ---
run_theme reset || fail "reset failed: $(cat "$tmp/err")"
[[ "$(base_size)" == 16 ]] || fail "reset left baseSize at $(base_size)"
[[ "$(tail -n1 "$tmp/gsettings.log")" == "reset org.gnome.desktop.interface text-scaling-factor" ]] \
    || fail "reset did not reset GTK: $(tail -n1 "$tmp/gsettings.log")"
[[ "$(cat "$size_file")" == 11.5 ]] || fail "reset left terminal at $(cat "$size_file")"
[[ "$(tail -n1 "$tmp/hook.log")" == "theme-set text-size=16" ]] || fail "reset did not fire the hook"
run_theme 16 || fail "text-size 16 failed"
[[ "$(tail -n1 "$tmp/gsettings.log")" == reset* ]] || fail "16 should reset GTK, not set a factor"
echo "ok   reset: baseSize=16 gtk reset terminal=11.5"

# --- 5. show: the three current values, on one line each ---
run_theme show || fail "show failed: $(cat "$tmp/err")"
[[ "$(cat "$tmp/out")" == $'text size: 16 px\ngtk text-scaling-factor: 1.0\nterminal font: 11.5 pt' ]] \
    || fail "show printed: $(cat "$tmp/out")"
run_theme || fail "bare text-size failed"
[[ "$(cat "$tmp/out")" == "text size: 16 px"* ]] || fail "bare text-size is not show"
echo "ok   show"

# --- 6. range and refusals: nothing written on a bad size or a bad config ---
before="$(cat "$config")"
for bad in 8 25 abc 1.5 ""; do
    run_theme "$bad" && fail "text-size '$bad' was accepted"
    grep -q '9 to 24' "$tmp/err" || fail "no range message for '$bad': $(cat "$tmp/err")"
done
[[ "$(cat "$config")" == "$before" ]] || fail "a rejected size still touched config.json"
[[ "$(cat "$size_file")" == 11.5 ]] || fail "a rejected size still touched the terminal size"
printf 'not json' > "$config"
run_theme 18 && fail "wrote into a config.json that is not JSON"
[[ "$(cat "$config")" == 'not json' ]] || fail "invalid config.json was replaced"
rm "$config"
run_theme 18 && fail "text-size succeeded with no config.json"
[[ ! -e "$config" ]] || fail "a config.json was invented"
echo "ok   refusals: 8, 25, abc, 1.5, empty, non-JSON config, missing config"

# --- 7. wezterm reads the file the tool writes, and falls back to 11.5 ---
if command -v lua >/dev/null; then
    wez_size() {
        HOME="$home" XDG_CONFIG_HOME="$home/.config" WEZTERM_LUA="$WEZTERM" lua -e '
            package.preload.wezterm = function()
                return { config_builder = function() return {} end,
                         add_to_config_reload_watch_list = function() end }
            end
            print(dofile(os.getenv("WEZTERM_LUA")).font_size)' 2>&1
    }
    echo '{"appearance":{}}' > "$config"
    run_theme 20 || fail "text-size 20 for wezterm failed"
    [[ "$(wez_size)" == 14.5 ]] || fail "wezterm read $(wez_size), the tool wrote $(cat "$size_file")"
    rm "$size_file"
    [[ "$(wez_size)" == 11.5 ]] || fail "wezterm without the file: $(wez_size)"
    printf 'huge\n' > "$size_file"
    [[ "$(wez_size)" == 11.5 ]] || fail "wezterm on a non-number: $(wez_size)"
    grep -q 'pcall(io.open' "$WEZTERM" || fail "wezterm.lua no longer guards the read with pcall"
    echo "ok   wezterm: 14.5 from the file, 11.5 without it or on garbage"
else
    echo "lua not installed; skipping the wezterm read check" >&2
fi

# --- 8. the two files that may not grow, and the QML still parses ---
for f in "$APPEARANCE" "$CONFIG_QML"; do
    rel="${f#"$ROOT"/}"
    allowed="$(awk -F'\t' -v p="$rel" '$1 == p { print $2 }' "$ALLOW")"
    lines="$(awk 'END { print NR }' "$f")"
    [[ "$lines" == "$allowed" ]] || fail "$rel is $lines lines, the allow-list pins $allowed"
done
echo "ok   Appearance.qml and Config.qml are still at their allow-listed length"

QMLLINT=/usr/lib/qt6/bin/qmllint
if [[ -x "$QMLLINT" ]]; then
    lint="$tmp/lint"; mkdir -p "$lint"; ln -s "$Q" "$lint/qs"
    for f in "$APPEARANCE" "$FONTS_QML"; do
        out="$("$QMLLINT" -I "$lint" -I /usr/lib/qt6/qml "$f" 2>&1)" \
            || { echo "$out" | head -20 >&2; fail "qmllint rejects ${f#"$ROOT"/}"; }
        grep -qE '^Error' <<< "$out" && { echo "$out" | grep -A3 '^Error' >&2; fail "qmllint error in ${f#"$ROOT"/}"; }
    done
    echo "ok   qmllint: Appearance.qml and FontsSection.qml parse without errors"
else
    echo "qt6 qmllint not installed; skipping the QML parse check" >&2
fi

echo "text size test passed"
