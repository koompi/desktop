#!/usr/bin/env bash
# The lock screen's PAM stacks, checked at the source and driven for real where
# that needs neither a password nor the fingerprint reader:
#   - the fingerprint stack ends in an explicit deny and its directory carries
#     an `other` that denies, so libpam has nothing to fall through to;
#   - the shell only unlocks on PamResult.Success and treats a PamContext that
#     cannot start as a failed attempt;
#   - a PamContext pointed at a missing or unloadable config never reports
#     success (probed with `qs -p` against temp directories; pam_fprintd is
#     never loaded, so fprintd and the reader are never touched).
# What cannot be automated: a successful password or fingerprint unlock, since
# both need the real credential. The password stack is the system's own
# /etc/pam.d/login (Quickshell's default), which this repo does not ship.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
LOCK="$REPO_ROOT/dots/.config/quickshell/koompi/modules/common/panels/lock"
PAM="$LOCK/pam"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

# --- fingerprint stack -------------------------------------------------------
[[ -f "$PAM/fprintd.conf" ]] || fail "pam/fprintd.conf is missing"
[[ -f "$PAM/other" ]] || fail "pam/other is missing (libpam looks it up for every service in the directory)"
mapfile -t auth_lines < <(grep -E '^auth[[:space:]]' "$PAM/fprintd.conf")
[[ ${#auth_lines[@]} -eq 2 ]] || fail "pam/fprintd.conf must have exactly two auth lines, has ${#auth_lines[@]}"
grep -qE '^auth[[:space:]]+sufficient[[:space:]]+pam_fprintd\.so[[:space:]]*$' <<< "${auth_lines[0]}" \
    || fail "pam/fprintd.conf first auth line is not 'auth sufficient pam_fprintd.so'"
grep -qE '^auth[[:space:]]+required[[:space:]]+pam_deny\.so[[:space:]]*$' <<< "${auth_lines[1]}" \
    || fail "pam/fprintd.conf does not end its auth stack with 'auth required pam_deny.so'"
for type in auth account password session; do
    grep -qE "^${type}[[:space:]]+required[[:space:]]+pam_deny\.so[[:space:]]*$" "$PAM/other" \
        || fail "pam/other does not deny '$type'"
done
grep -rq 'pam_permit' "$PAM" && fail "pam/ contains pam_permit"
echo "ok   pam/: fprintd.conf is sufficient pam_fprintd + required pam_deny; other denies all four types"

# --- the shell's handling ------------------------------------------------------
ctx="$LOCK/LockContext.qml"
unlocks="$(grep -c 'root.unlocked(root.targetAction)' "$ctx")"
[[ "$unlocks" -eq 2 ]] || fail "LockContext emits unlocked from $unlocks places, expected 2 (password, fingerprint)"
guarded="$(grep -B2 'root.unlocked(root.targetAction)' "$ctx" | grep -c 'if (result == PamResult.Success) {')"
[[ "$guarded" -eq 2 ]] || fail "LockContext emits unlocked outside an 'if (result == PamResult.Success)' branch"
grep -q 'if (!pam.start())' "$ctx" || fail "LockContext ignores pam.start() returning false (field stays disabled forever)"
grep -q 'if (!fingerPam.start())' "$ctx" || fail "LockContext ignores fingerPam.start() returning false"
[[ "$(grep -c 'configDirectory:' "$ctx")" -eq 1 ]] || fail "more than one PamContext overrides configDirectory"
grep -q 'config: "fprintd.conf"' "$ctx" || fail "fingerprint PamContext no longer uses fprintd.conf"
grep -q 'SetLockedHint' "$LOCK/LockScreen.qml" || fail "LockScreen does not publish the lock through logind's LockedHint"
echo "ok   LockContext: unlock gated on PamResult.Success twice, start() failures handled; LockScreen sets LockedHint"

if [[ ! -f /etc/pam.d/login ]]; then
    echo "note: /etc/pam.d/login is missing on this machine; the password PamContext (Quickshell default config 'login') cannot start here"
fi

if ! command -v qs > /dev/null 2>&1; then
    echo "skip: quickshell (qs) not installed, static checks only"
    exit 0
fi

# --- PamContext against broken configs ------------------------------------------
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/probe" "$WORK/self-contained" "$WORK/bare" "$WORK/control"

cat > "$WORK/probe/probe.qml" <<'QML'
import QtQuick
import Quickshell
import Quickshell.Services.Pam

ShellRoot {
    PamContext {
        id: ctx
        configDirectory: Quickshell.env("LOCK_PAM_DIR")
        config: Quickshell.env("LOCK_PAM_CONFIG")
        onPamMessage: {
            console.log("[probe] message=" + JSON.stringify(this.message) + " responseRequired=" + this.responseRequired);
            if (this.responseRequired) this.respond("");
        }
        onCompleted: r => { console.log("[probe] completed=" + r + " success=" + (r === PamResult.Success)); Qt.callLater(Qt.quit); }
    }
    Component.onCompleted: {
        const started = ctx.start();
        console.log("[probe] start=" + started);
        // quit() before the event loop runs is dropped; callLater lands inside it.
        if (!started) Qt.callLater(Qt.quit);
    }
}
QML

# Runs the probe and prints its "[probe]" lines, colour stripped.
probe() {
    LOCK_PAM_DIR="$1" LOCK_PAM_CONFIG="$2" timeout 20 qs -p "$WORK/probe/probe.qml" 2>&1 \
        | sed 's/\x1b\[[0-9;]*m//g' | grep -o '\[probe\].*'
}

# The shipped stack with pam_fprintd replaced by a module that cannot be
# loaded: the shape the lock screen runs when the module is missing.
sed 's#[[:space:]]pam_fprintd\.so#\t/nonexistent/pam_fprintd.so#' "$PAM/fprintd.conf" > "$WORK/self-contained/fprintd.conf"
cp "$PAM/other" "$WORK/self-contained/other"
grep -q '/nonexistent/pam_fprintd.so' "$WORK/self-contained/fprintd.conf" || fail "could not rewrite pam_fprintd.so to an unloadable path"
# The stack as it shipped before: one sufficient line, no deny, no other.
printf 'auth    sufficient    /nonexistent/pam_fprintd.so\n' > "$WORK/bare/fprintd.conf"
# Positive control: proves the probe reports success when libpam grants it.
# Carries `other` too, so only the bare directory can log the missing-default line.
printf 'auth    sufficient    pam_permit.so\n' > "$WORK/control/permit.conf"
cp "$PAM/other" "$WORK/control/other"

journal_since="$(date '+%Y-%m-%d %H:%M:%S')"
sleep 1

out="$(probe "$WORK/self-contained" "missing.conf")"
grep -q '^\[probe\] start=false' <<< "$out" || fail "missing config: PamContext.start() should return false, got: $out"
grep -q 'completed=' <<< "$out" && fail "missing config: PamContext completed anyway: $out"
echo "ok   missing config: start() is false and nothing completes"

out="$(probe "$WORK/self-contained" "fprintd.conf")"
grep -q '^\[probe\] start=true' <<< "$out" || fail "unloadable module: PamContext did not start: $out"
grep -q 'completed=.*success=false' <<< "$out" || fail "unloadable module: expected a non-success completion, got: $out"
grep -q 'finger' <<< "$out" && fail "unloadable module: the probe reached fprintd: $out"
echo "ok   shipped stack with an unloadable pam_fprintd: completes without success ($(grep -o 'completed=[0-9]*' <<< "$out"))"

out="$(probe "$WORK/bare" "fprintd.conf")"
grep -q 'completed=.*success=false' <<< "$out" || fail "bare sufficient-only stack: expected a non-success completion, got: $out"
echo "ok   sufficient-only stack with an unloadable module: libpam's own fallback also denies ($(grep -o 'completed=[0-9]*' <<< "$out"))"

out="$(probe "$WORK/control" "permit.conf")"
grep -q 'completed=0 success=true' <<< "$out" || fail "positive control: pam_permit should succeed, got: $out"
echo "ok   positive control: the probe reports success when libpam grants it"

if journalctl -q --since "$journal_since" -o cat > "$WORK/journal.txt" 2>/dev/null; then
    hits="$(grep -c 'no default config other' "$WORK/journal.txt")"
    # The bare directory has no `other`, so exactly that run must have logged it.
    [[ "$hits" -ge 1 ]] || { echo "note: journal shows no '_pam_init_handlers' line at all; cannot check the other-file effect"; exit 0; }
    [[ "$hits" -eq 1 ]] || fail "expected only the bare directory to log 'no default config other', journal has $hits lines"
    echo "ok   journal: only the directory without 'other' logged '_pam_init_handlers: no default config other'"
else
    echo "skip: system journal not readable, other-file journal check not run"
fi
