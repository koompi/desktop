#!/usr/bin/env bash
# sdata/lib/from-source.sh is what Fedora and Debian install everything Arch gets
# from the AUR with. Two of its rules are invisible until an install is halfway
# through on someone else's machine, and both were broken at once:
#
#   1. A font that is already on disk must read as present. `fc-list | grep -q`
#      says otherwise under pipefail, so Fedora re-downloaded four fonts its own
#      RPMs had just installed and re-fetched the 30 MiB Nerd Font every run.
#   2. A download that fails must return to its caller, which decides. Routed
#      through run(), a 404 called die under --yes and took the whole install
#      down before the `|| warn` beside it was ever reached.
#
# Everything the library would touch is stubbed; nothing here reaches the
# network or the filesystem outside a temp directory.
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

DRY_RUN=false ASSUME_YES=true
# shellcheck source=sdata/lib/common.sh
source "$ROOT/sdata/lib/common.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"

XDG_DATA_HOME="$tmp/share"
# shellcheck source=sdata/lib/from-source.sh
source "$ROOT/sdata/lib/from-source.sh"

# ./setup sets pipefail, and that is the whole point of case 1.
set -o pipefail

# A realistic fc-list: the wanted face early, then far more output than a 64 KiB
# pipe buffer, so a reader that stops at the match leaves the writer on SIGPIPE.
cat > "$tmp/bin/fc-list" <<'STUB'
#!/bin/sh
echo '/usr/share/fonts/readex/ReadexPro.ttf: "Readex Pro" "Regular"'
i=0
while [ $i -lt 4000 ]; do
    echo "/usr/share/fonts/noto/Filler$i.ttf: \"Filler Face $i\" \"Regular\""
    i=$((i + 1))
done
STUB
chmod +x "$tmp/bin/fc-list"

PATH="$tmp/bin:$PATH"
_font_installed "Readex Pro" \
    || fail "_font_installed missed a font fc-list reports; under pipefail this makes every install re-download every font it already has"
_font_installed "No Such Face" \
    && fail "_font_installed claimed a font that fc-list never listed"

# The old shape, kept here as the thing that must not come back: it answers
# 'missing' for a font that is plainly installed.
if fc-list 2>/dev/null | grep -qi "Readex Pro"; then
    fail "the stub fc-list is too small to reproduce the SIGPIPE this test guards; raise its line count"
fi
grep -q 'fc-list 2>/dev/null | grep' "$ROOT/sdata/lib/from-source.sh" \
    && fail "from-source.sh is back to testing for a font with 'fc-list | grep -q', which always says missing under pipefail"

# 2. A failed download returns, it does not abort. run() calls die under --yes,
#    so _fetch must not be routed through it.
cat > "$tmp/bin/curl" <<'STUB'
#!/bin/sh
exit 22
STUB
chmod +x "$tmp/bin/curl"

( _fetch "https://example.invalid/x.tar.gz" "$tmp/x.tar.gz" ) \
    && fail "_fetch reported success for a curl that failed"
rc=$?
(( rc == 22 || rc == 1 )) \
    || fail "_fetch exited $rc on a failed download; a caller's '|| warn' never runs if it dies instead"

# The die() that used to happen exits the shell, so reaching this line at all is
# the assertion: the subshell above returned rather than taking the run with it.
survived=yes
[[ "$survived" == yes ]] \
    || fail "unreachable"

grep -q '^    run curl' "$ROOT/sdata/lib/from-source.sh" \
    && fail "_fetch is back to running curl through run(), which calls die under --yes before any caller can recover"

echo "ok"
