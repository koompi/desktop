#!/usr/bin/env bash
# koompi-open-url must send a link to the browser window focused most recently,
# focus that window, and strip the koompi-widget desktop prefix before anything
# it launches or queries sees it. With no browser window it must fall back to
# the session default and focus that browser's first window once it maps.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO_ROOT/dots/.local/bin/koompi-open-url"
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
command -v jq >/dev/null || { echo "skip: jq not installed"; exit 0; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
stub="$tmp/bin"
mkdir -p "$stub" "$tmp/share/applications"
for cmd in bash jq seq sleep cat; do
    path="$(command -v "$cmd")" || fail "test host has no $cmd"
    ln -s "$path" "$stub/$cmd"
done
touch "$tmp/share/applications/brave-browser.desktop" "$tmp/share/applications/google-chrome.desktop"

cat > "$stub/hyprctl" <<'STUB'
#!/usr/bin/env bash
case "$1" in
    clients)
        if [[ -n ${STUB_NO_BROWSER:-} ]]; then
            n=$(cat "$STUB_CALLS" 2>/dev/null || echo 0); echo $((n + 1)) > "$STUB_CALLS"
            if (( n >= 3 )); then
                echo '[{"address":"0xc","mapped":true,"class":"google-chrome","workspace":{"name":"9"},"focusHistoryID":0}]'
            else
                echo '[{"address":"0xt","mapped":true,"class":"TelegramDesktop","workspace":{"name":"special:telegram"},"focusHistoryID":0}]'
            fi
        else
            echo '[{"address":"0xt","mapped":true,"class":"TelegramDesktop","workspace":{"name":"special:telegram"},"focusHistoryID":0},
                   {"address":"0xb","mapped":true,"class":"brave-browser","workspace":{"name":"9"},"focusHistoryID":1},
                   {"address":"0xc","mapped":true,"class":"google-chrome","workspace":{"name":"9"},"focusHistoryID":3},
                   {"address":"0xw","mapped":true,"class":"chrome-web.whatsapp.com__-Default","workspace":{"name":"special:whatsapp"},"focusHistoryID":2}]'
        fi ;;
    dispatch) printf '%s\n' "$2" >> "$STUB_DISPATCH" ;;
esac
STUB
cat > "$stub/koompi-launch" <<'STUB'
#!/usr/bin/env bash
printf 'desktop=%s args=%s\n' "$XDG_CURRENT_DESKTOP" "$*" >> "$STUB_LAUNCH"
STUB
cat > "$stub/xdg-settings" <<'STUB'
#!/usr/bin/env bash
printf 'desktop=%s\n' "$XDG_CURRENT_DESKTOP" >> "$STUB_QUERY"
echo google-chrome.desktop
STUB
chmod +x "$stub/hyprctl" "$stub/koompi-launch" "$stub/xdg-settings"

run_open() {
    env -i PATH="$stub" HOME="$tmp" XDG_DATA_HOME="$tmp/share" XDG_DATA_DIRS="$tmp/none" \
        XDG_CURRENT_DESKTOP="koompi-widget:KOOMPI:Hyprland" \
        STUB_DISPATCH="$tmp/dispatch.log" STUB_LAUNCH="$tmp/launch.log" \
        STUB_QUERY="$tmp/query.log" STUB_CALLS="$tmp/calls" "$@" \
        bash "$SCRIPT" "https://example.com/a?b=1" > "$tmp/out" 2>&1
}

run_open
(( $? == 0 )) || fail "open exited non-zero: $(cat "$tmp/out")"
grep -qx 'desktop=KOOMPI:Hyprland args=brave-browser.desktop https://example.com/a?b=1' "$tmp/launch.log" \
    || fail "expected the most recently focused browser (brave) with the prefix stripped, got: $(cat "$tmp/launch.log")"
grep -q 'address:0xb' "$tmp/dispatch.log" || fail "brave's window was not focused: $(cat "$tmp/dispatch.log")"
[[ -e $tmp/query.log ]] && fail "default browser was queried although a browser window was open"
rm -f "$tmp/launch.log" "$tmp/dispatch.log"

run_open STUB_NO_BROWSER=1
(( $? == 0 )) || fail "fallback open exited non-zero: $(cat "$tmp/out")"
grep -qx 'desktop=KOOMPI:Hyprland' "$tmp/query.log" || fail "default lookup saw the widget prefix: $(cat "$tmp/query.log")"
grep -qx 'desktop=KOOMPI:Hyprland args=google-chrome.desktop https://example.com/a?b=1' "$tmp/launch.log" \
    || fail "expected the default browser, got: $(cat "$tmp/launch.log")"
grep -q 'address:0xc' "$tmp/dispatch.log" || fail "the fresh browser window was not focused: $(cat "$tmp/dispatch.log")"

env -i PATH="$stub" HOME="$tmp" STUB_DISPATCH="$tmp/d" STUB_LAUNCH="$tmp/l" STUB_QUERY="$tmp/q" STUB_CALLS="$tmp/c" \
    bash "$SCRIPT" "file:///etc/passwd" > "$tmp/out" 2>&1 && fail "a non-http URL was accepted"

printf 'open-url test passed\n'
