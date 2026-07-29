#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="${KOOMPI_CONFIG_FILE:-$HOME/.config/koompi/config.json}"
DEFAULT_ROOT="$HOME/.config/koompi/wallpapers"
DEFAULT_LIBRARY="$DEFAULT_ROOT/library"
LOG_DIR="${KOOMPI_LOG_DIR:-$HOME/.local/state/koompi/logs}"
LOG_FILE="$LOG_DIR/wallpaper.log"

usage() {
    cat <<'USAGE'
Usage: koompi-wallpaper.sh <command> [args]

Commands:
  init
      Create KOOMPI wallpaper directories and ensure config defaults exist.

  status
      Print workspace wallpaper status from ~/.config/koompi/config.json.

  mode <1-10> inherit|static
      Set one workspace mode. Does not enable the feature globally.

  set <1-10> /path/to/image
      Set one workspace static path and mode=static. Does not enable the feature globally.

  seed
      Give every workspace (1-10) its own distinct random wallpaper.

  set-active /path/to/image
      Same as set, but targets whichever workspace is active right now. This is
      what the random wallpaper keybind uses, so a re-roll only ever touches the
      workspace you are looking at.

Notes:
  - Source images are read from ~/.config/koompi/wallpapers/library.
  - Workspaces point straight at their source image; nothing is copied or generated.
  - This helper does not call switchwall.sh, matugen, KDE, GNOME, GTK, or Qt theming.
USAGE
}

log() {
    mkdir -p "$LOG_DIR"
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE"
}

fail() {
    printf 'koompi-wallpaper: %s\n' "$*" >&2
    log "ERROR: $*"
    exit 1
}

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"
}

json_get() {
    local filter="$1"
    jq -r "$filter" "$CONFIG_FILE"
}

commit_config() {
    local tmp="$1"
    jq -e 'type == "object"' "$tmp" >/dev/null 2>&1 || { rm -f "$tmp"; fail "Refusing to write invalid config: $CONFIG_FILE"; }
    mv "$tmp" "$CONFIG_FILE"
}

json_update() {
    local filter="$1"
    local tmp
    tmp="$(mktemp)"
    jq "$filter" "$CONFIG_FILE" > "$tmp"
    commit_config "$tmp"
}

ensure_config_file() {
    need_cmd jq
    if [[ ! -f "$CONFIG_FILE" ]]; then
        fail "Config file not found: $CONFIG_FILE"
    fi
    jq -e 'type == "object"' "$CONFIG_FILE" >/dev/null || fail "Config file is not valid JSON: $CONFIG_FILE"
}

ensure_dirs() {
    local library
    library="$(json_get '.background.workspaceWallpapers.libraryPath // "'"$DEFAULT_LIBRARY"'"')"
    mkdir -p "$library/abstract" "$library/static" "$LOG_DIR"
}

ensure_workspace_config() {
    # shellcheck disable=SC2016 # this is a jq program, $i is jq's variable, not the shell's
    json_update '
      .background.workspaceWallpapers = (.background.workspaceWallpapers // {}) |
      .background.workspaceWallpapers.enabled = (.background.workspaceWallpapers.enabled // false) |
      .background.workspaceWallpapers.defaultMode = (.background.workspaceWallpapers.defaultMode // "inherit") |
      .background.workspaceWallpapers.workspaces = (.background.workspaceWallpapers.workspaces // {}) |
      reduce range(1; 11) as $i (.;
        .background.workspaceWallpapers.workspaces["ws\($i)"] =
          (.background.workspaceWallpapers.workspaces["ws\($i)"] // {"mode":"inherit","path":""}) |
        .background.workspaceWallpapers.workspaces["ws\($i)"].mode =
          (.background.workspaceWallpapers.workspaces["ws\($i)"].mode // "inherit") |
        .background.workspaceWallpapers.workspaces["ws\($i)"].path =
          (.background.workspaceWallpapers.workspaces["ws\($i)"].path // "")
      )
    '
}

cmd_init() {
    ensure_config_file
    ensure_workspace_config
    ensure_dirs
    log "init completed"
    printf 'KOOMPI wallpaper directories/config are ready.\n'
}

valid_workspace_number() {
    [[ "$1" =~ ^([1-9]|10)$ ]]
}

valid_mode() {
    case "$1" in
        inherit|static) return 0 ;;
        *) return 1 ;;
    esac
}

cmd_status() {
    ensure_config_file
    ensure_workspace_config
    ensure_dirs
    jq '.background.workspaceWallpapers' "$CONFIG_FILE"
}

cmd_mode() {
    ensure_config_file
    ensure_workspace_config
    local workspace="${1:-}"
    local mode="${2:-}"
    valid_workspace_number "$workspace" || fail "Workspace must be 1-10"
    valid_mode "$mode" || fail "Mode must be inherit or static"

    local key="ws$workspace"
    jq --arg key "$key" --arg mode "$mode" '
      .background.workspaceWallpapers.workspaces[$key].mode = $mode |
      if $mode == "inherit" then .background.workspaceWallpapers.workspaces[$key].path = "" else . end
    ' "$CONFIG_FILE" > "$CONFIG_FILE.tmp"
    commit_config "$CONFIG_FILE.tmp"
    log "mode $key -> $mode"
    printf 'Set %s mode to %s.\n' "$key" "$mode"
}

cmd_set() {
    ensure_config_file
    ensure_workspace_config
    local workspace="${1:-}"
    local path="${2:-}"
    valid_workspace_number "$workspace" || fail "Workspace must be 1-10"
    [[ -n "$path" ]] || fail "Image path is required"
    [[ -f "$path" ]] || fail "Image path does not exist: $path"
    # Config must hold an absolute path: the shell resolves it from its own cwd,
    # not from wherever this script happened to be run.
    path="$(realpath -- "$path")"
    # Select on mime type, not extension: several shipped library images have no
    # extension at all, and they are perfectly good wallpapers.
    case "$(file -b --mime-type "$path")" in
        image/*) ;;
        *) fail "Not an image file: $path" ;;
    esac

    local key="ws$workspace"
    jq --arg key "$key" --arg path "$path" '
      .background.workspaceWallpapers.workspaces[$key].mode = "static" |
      .background.workspaceWallpapers.workspaces[$key].path = $path
    ' "$CONFIG_FILE" > "$CONFIG_FILE.tmp"
    commit_config "$CONFIG_FILE.tmp"
    log "set $key static path -> $path"
    printf 'Set %s static wallpaper to %s.\n' "$key" "$path"
}

# Deal a distinct wallpaper to every workspace. With a pool smaller than ten
# the deal cycles, repeating as little as possible.
cmd_seed() {
    ensure_config_file
    ensure_workspace_config
    need_cmd shuf
    local library
    library="$(json_get '.background.workspaceWallpapers.libraryPath // "'"$DEFAULT_LIBRARY"'"')"
    local -a dirs=()
    [[ -d "$library" ]] && dirs+=("$library")
    [[ -d /usr/share/backgrounds/koompi ]] && dirs+=(/usr/share/backgrounds/koompi)
    local pictures_wallpapers="$HOME/Pictures/Wallpapers"
    [[ -d "$pictures_wallpapers" ]] && dirs+=("$pictures_wallpapers")
    [[ "${#dirs[@]}" -gt 0 ]] || fail "No wallpaper directory found to seed from"

    local -a images=()
    while IFS= read -r -d '' f; do
        case "$(file -b --mime-type "$f")" in
            image/*) images+=("$f") ;;
        esac
    done < <(find "${dirs[@]}" -type f -not -path '*/not-desktop-grade/*' -print0)
    [[ "${#images[@]}" -gt 0 ]] || fail "No images found in: ${dirs[*]}"

    mapfile -t shuffled < <(printf '%s
' "${images[@]}" | shuf)
    local i path
    for i in {1..10}; do
        path="${shuffled[$(( (i - 1) % ${#shuffled[@]} ))]}"
        jq --arg key "ws$i" --arg path "$path" '
          .background.workspaceWallpapers.workspaces[$key].mode = "static" |
          .background.workspaceWallpapers.workspaces[$key].path = $path
        ' "$CONFIG_FILE" > "$CONFIG_FILE.tmp"
        commit_config "$CONFIG_FILE.tmp"
        log "seed ws$i -> $path"
    done
    printf 'Seeded 10 workspaces from %s image(s).
' "${#shuffled[@]}"
}

cmd_set_active() {
    local path="${1:-}"
    local workspace
    need_cmd hyprctl
    workspace="$(hyprctl activeworkspace -j | jq -r '.id')"
    valid_workspace_number "$workspace" || fail "Active workspace $workspace is outside 1-10"
    cmd_set "$workspace" "$path"
}

main() {
    local command="${1:-}"
    case "$command" in
        init)
            shift
            [[ $# -eq 0 ]] || fail "init takes no arguments"
            cmd_init
            ;;
        status)
            shift
            [[ $# -eq 0 ]] || fail "status takes no arguments"
            cmd_status
            ;;
        mode)
            shift
            cmd_mode "$@"
            ;;
        set)
            shift
            cmd_set "$@"
            ;;
        set-active)
            shift
            cmd_set_active "$@"
            ;;
        seed)
            shift
            [[ $# -eq 0 ]] || fail "seed takes no arguments"
            cmd_seed
            ;;
        -h|--help|help|"")
            usage
            ;;
        *)
            usage >&2
            fail "Unknown command: $command"
            ;;
    esac
}

main "$@"
