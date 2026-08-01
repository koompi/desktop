#!/usr/bin/env bash
# Lid closed at 30%, flat by morning: a wedged btintel_pcie failed suspend 614
# times in one boot. setup_suspend_hook drops the module before sleep.
#
# Asserts on the hook text setups.sh ships, not a copy. modprobe is stubbed and
# the hook's /run and /sys paths are redirected, so this runs unprivileged.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail() { printf '%s\n--- modprobe calls ---\n%s\n' "$1" "$(cat "$tmp/modprobe.log" 2>/dev/null)" >&2; exit 1; }

# Stands in for sdata/lib/common.sh.
step() { :; }; info() { :; }; ok() { :; }; warn() { :; }; run() { :; }
have() { return 0; }
sudo_write() { printf '%s\n' "$2" > "$tmp/hook.captured"; }

# shellcheck source=sdata/install/setups.sh
source "$REPO_ROOT/sdata/install/setups.sh" 2>/dev/null || true
declare -F setup_suspend_hook >/dev/null ||
    fail 'setups.sh no longer defines setup_suspend_hook'
setup_suspend_hook
[[ -s "$tmp/hook.captured" ]] || fail 'setup_suspend_hook wrote no hook'

# Redirect the absolute paths so the hook runs unprivileged.
hook="$tmp/hook"
sed -e "s|/run/koompi-btintel-pcie-off|$tmp/stamp|" \
    -e "s|/sys/module/btintel_pcie|$tmp/sysmodule|" \
    "$tmp/hook.captured" > "$hook"
chmod +x "$hook"

grep -q "$tmp/stamp" "$hook"      || fail 'the hook no longer uses a /run stamp file'
grep -q "$tmp/sysmodule" "$hook"  || fail 'the hook no longer checks /sys/module/btintel_pcie'

stub="$tmp/bin"
mkdir -p "$stub"
cat > "$stub/modprobe" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$MODPROBE_LOG"
# MODPROBE_FAIL = a module the kernel will not release.
[[ "$*" == "-r btintel_pcie" && -e "$MODPROBE_FAIL" ]] && exit 1
exit 0
EOF
chmod +x "$stub/modprobe"
export MODPROBE_LOG="$tmp/modprobe.log"
export MODPROBE_FAIL="$tmp/fail"
PATH="$stub:$PATH"

# 1. Has the hardware: pre unloads and records it.
mkdir -p "$tmp/sysmodule"
: > "$MODPROBE_LOG"
"$hook" pre || fail 'the hook failed on pre'
grep -qFx -- '-r btintel_pcie' "$MODPROBE_LOG" || fail 'pre did not unload btintel_pcie'
[[ -e "$tmp/stamp" ]] || fail 'pre unloaded the module but recorded nothing for post'

# 2. Resume puts Bluetooth back.
: > "$MODPROBE_LOG"
"$hook" post || fail 'the hook failed on post'
grep -qFx -- 'btintel_pcie' "$MODPROBE_LOG" || fail 'post did not reload btintel_pcie'
[[ -e "$tmp/stamp" ]] && fail 'post left its stamp behind, so the next post would reload blindly'

# 3. No such device: do nothing. The hook ships to every machine.
rm -rf "$tmp/sysmodule"
: > "$MODPROBE_LOG"
"$hook" pre || fail 'the hook failed on pre with no btintel_pcie present'
[[ -s "$MODPROBE_LOG" ]] && fail 'pre touched modprobe on a machine with no btintel_pcie'
[[ -e "$tmp/stamp" ]] && fail 'pre wrote a stamp without unloading anything'

# 4. Unload refused: say so, and do not reload on post.
mkdir -p "$tmp/sysmodule"
touch "$MODPROBE_FAIL"
: > "$MODPROBE_LOG"
stderr="$("$hook" pre 2>&1 >/dev/null)" || fail 'the hook failed on a refused unload'
[[ "$stderr" == *btintel_pcie* ]] || fail 'a refused unload was silent'
[[ -e "$tmp/stamp" ]] && fail 'a refused unload still recorded a stamp'

: > "$MODPROBE_LOG"
"$hook" post || fail 'the hook failed on post after a refused unload'
[[ -s "$MODPROBE_LOG" ]] && fail 'post reloaded a module that pre never unloaded'

printf 'suspend hook test passed\n'
