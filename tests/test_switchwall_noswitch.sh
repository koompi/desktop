#!/usr/bin/env bash
# switchwall.sh --noswitch is what koompi-theme runs. Three ways it went wrong
# outside the happy path: a config with no wallpaper yet made jq print `null`,
# which was then stored as the wallpaper path; outside a Hyprland session the
# venv variable is unset and "/bin/activate" was sourced without a word; and the
# AI category was written into a directory nothing had created.
#
# Runs a copy of the colors/ tree with every side-effecting helper stubbed, on a
# throwaway config. Nothing here touches the real session or ~/.config.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
COLORS="$REPO_ROOT/dots/.config/quickshell/koompi/scripts/colors"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
stub="$tmp/bin"; mark="$tmp/mark"
mkdir -p "$stub" "$mark" "$tmp/home" "$tmp/config/koompi" "$tmp/config/hypr/custom/scripts" "$tmp/state" "$tmp/cache"

# The script under test, beside stand-ins for the helpers it forks.
cp -r "$COLORS" "$tmp/colors"
mkdir -p "$tmp/ai"
for helper in applycolor.sh code/material-code-set-color.sh zed/zed-set-theme.sh agents/agent-theme-sync.sh; do
    printf '#!/usr/bin/env bash\nexit 0\n' > "$tmp/colors/$helper"
done
printf '#!/usr/bin/env bash\nprintf nature\n' > "$tmp/ai/gemini-categorize-wallpaper.sh"
chmod +x "$tmp/colors"/*.sh "$tmp/colors"/*/*.sh "$tmp/ai"/*.sh
switchwall="$tmp/colors/switchwall.sh"

# PATH is the stub dir alone, so the real pkill, matugen and gsettings are
# unreachable. Coreutils and jq come in by symlink.
for cmd in bash jq dirname basename mkdir cat date mv rm tr xargs mktemp head chmod touch; do
    path="$(command -v "$cmd")" || fail "test host has no $cmd"
    ln -s "$path" "$stub/$cmd"
done
for cmd in matugen python3 pkill notify-send kdialog xdg-user-dir; do
    printf '#!/usr/bin/env bash\ntouch "%s/%s"\nexit 0\n' "$mark" "$cmd" > "$stub/$cmd"
    chmod +x "$stub/$cmd"
done
cat > "$stub/gsettings" <<'STUB'
#!/usr/bin/env bash
[[ "$1" == get ]] && echo "'prefer-dark'"
exit 0
STUB
cat > "$stub/hyprctl" <<'STUB'
#!/usr/bin/env bash
echo '[{"name":"eDP-1","width":1920,"height":1080}]'
STUB
chmod +x "$stub/gsettings" "$stub/hyprctl"

config="$tmp/config/koompi/config.json"
img="$tmp/wall.png"; : > "$img"

run_switchwall() {
    rm -f "$mark"/*
    env -i PATH="$stub" HOME="$tmp/home" \
        XDG_CONFIG_HOME="$tmp/config" XDG_STATE_HOME="$tmp/state" XDG_CACHE_HOME="$tmp/cache" \
        bash "$switchwall" "$@" > "$tmp/out" 2> "$tmp/err"
}

# 1. No wallpaper chosen yet: must abort, and must not store "null".
jq -n '{background: {}, appearance: {palette: {type: "scheme-tonal-spot"}}}' > "$config"
run_switchwall --noswitch
status=$?
(( status == 0 )) || fail "--noswitch with no wallpaper exited $status: $(cat "$tmp/err")"
grep -q '^Aborted$' "$tmp/out" || fail "expected 'Aborted' with no wallpaper, got: $(cat "$tmp/out")"
stored="$(jq -r '.background.wallpaperPath // "unset"' "$config")"
[[ "$stored" == unset ]] || fail "wallpaperPath was written as '$stored' on a config that never had one"
[[ ! -e "$mark/matugen" ]] || fail "matugen ran against a wallpaper that does not exist"

# 2. Wallpaper set, no venv anywhere: must say so and stop before matugen.
jq -n --arg img "$img" '{background: {wallpaperPath: $img}, appearance: {palette: {type: "scheme-tonal-spot"}}}' > "$config"
run_switchwall --noswitch
status=$?
(( status != 0 )) || fail "a missing venv exited 0"
grep -q 'no Python venv' "$tmp/err" || fail "a missing venv was not reported: $(cat "$tmp/err")"
[[ ! -e "$mark/matugen" ]] || fail "matugen ran with no venv; the theme would be half-applied"

# 3. Venv at the default path (no env var, as from a plain terminal), AI
#    categorisation on: the run completes and the category lands in a directory
#    that did not exist beforehand.
mkdir -p "$tmp/state/quickshell/.venv/bin"
printf 'deactivate() { :; }\n' > "$tmp/state/quickshell/.venv/bin/activate"
jq '.background.widgets.clock.cookie.aiStyling = true' "$config" > "$config.new" && mv "$config.new" "$config"
[[ ! -d "$tmp/state/quickshell/user/generated/wallpaper" ]] || fail "test setup: category dir exists before the run"
run_switchwall --noswitch
status=$?
(( status == 0 )) || fail "run with a venv exited $status: $(cat "$tmp/err")"
[[ -e "$mark/matugen" ]] || fail "matugen did not run although the venv was found"
[[ -f "$tmp/state/quickshell/user/generated/material_colors.scss" ]] || fail "material_colors.scss was not written"
[[ "$(jq -r '.background.wallpaperPath' "$config")" == "$img" ]] || fail "wallpaperPath changed on --noswitch"

category="$tmp/state/quickshell/user/generated/wallpaper/category.txt"
for _ in $(seq 1 40); do
    [[ -s "$category" ]] && break
    sleep 0.05
done
[[ -s "$category" ]] || fail "category.txt was never written (categorize_wallpaper runs in the background)"
[[ "$(cat "$category")" == nature ]] || fail "category.txt holds '$(cat "$category")', expected 'nature'"

printf 'switchwall --noswitch test passed\n'
