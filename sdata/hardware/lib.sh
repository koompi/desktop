# shellcheck shell=bash
# Sourced by every quirk script here. apply-hardware exports KOOMPI_HW_DRY_RUN
# (print decisions, change nothing) and KOOMPI_HW_PREFIX (fake root for tests).
# Decision lines never start with "skip:": tests/run.sh reads that as a test
# that could not run.

: "${KOOMPI_HW_DRY_RUN:=false}"
: "${KOOMPI_HW_PREFIX:=}"

hw_not_applied() {
    printf 'not applied: %s\n' "$*"
    exit 0
}

hw_do() {
    if [[ "$KOOMPI_HW_DRY_RUN" == true ]]; then
        printf 'would run: %s\n' "$*"
        return 0
    fi
    printf 'run: %s\n' "$*"
    "$@"
}

# tmp + mv: a reader never sees a half-written config
hw_write() {
    local path="$1" content="$2" dir tmp
    if [[ "$KOOMPI_HW_DRY_RUN" == true ]]; then
        printf 'would write: %s\n' "$path"
        return 0
    fi
    printf 'write: %s\n' "$path"
    dir="$(dirname -- "$path")"
    mkdir -p -- "$dir"
    tmp="$(mktemp "$dir/.koompi-hw.XXXXXX")"
    printf '%s\n' "$content" > "$tmp"
    chmod 644 "$tmp"
    mv -f -- "$tmp" "$path"
}

hw_file_is() {
    local path="$1" content="$2"
    [[ -f "$path" ]] && [[ "$(< "$path")" == "$content" ]]
}

# on disk, not modprobe: in the install chroot uname -r is the live ISO's kernel
hw_kernel_ships() {
    compgen -G "$KOOMPI_HW_PREFIX/usr/lib/modules/*/kernel/$1.ko*" > /dev/null
}

# sd_booted(3); a chroot has systemctl and no pid 1 to talk to
hw_systemd_running() {
    [[ -z "$KOOMPI_HW_PREFIX" && -d /run/systemd/system ]]
}
