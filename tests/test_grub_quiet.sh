#!/usr/bin/env bash
# quiet_grub_entries strips GRUB's "Loading ..." echoes without breaking the
# config. A malformed grub.cfg is an unbootable machine, so the parse check
# matters as much as the deletion.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

# shellcheck source=installer/src/post_install.sh
source "$ROOT/installer/src/post_install.sh"

write_cfg() {
    cat > "$1" <<'EOF'
menuentry 'KOOMPI OS Linux' --class koompi {
	load_video
	set gfxpayload=keep
	echo	'Loading Linux linux ...'
	linux	/vmlinuz-linux root=UUID=deadbeef rw quiet splash
	echo	'Loading initial ramdisk ...'
	initrd	/intel-ucode.img /initramfs-linux.img
}
EOF
}

# 1. The echoes go, the boot commands stay.
CFG="$TEST_ROOT/grub.cfg"
write_cfg "$CFG"
KOOMPI_GRUB_CFG="$CFG" quiet_grub_entries >/dev/null

grep -q "Loading" "$CFG" && { echo "FAIL: a 'Loading' line survived"; exit 1; }
grep -q "^	linux	/vmlinuz-linux" "$CFG" || { echo "FAIL: linux line was eaten"; exit 1; }
grep -q "^	initrd	/intel-ucode.img" "$CFG" || { echo "FAIL: initrd line was eaten"; exit 1; }
grep -q "set gfxpayload=keep" "$CFG" || { echo "FAIL: unrelated line was eaten"; exit 1; }

# 2. Still parses. This is the check that stands between a typo and a brick.
if command -v grub-script-check &>/dev/null; then
    grub-script-check "$CFG" || { echo "FAIL: stripped config does not parse"; exit 1; }
fi

# 3. Idempotent: a second pass finds nothing and changes nothing.
before="$(cat "$CFG")"
KOOMPI_GRUB_CFG="$CFG" quiet_grub_entries >/dev/null
[[ "$before" == "$(cat "$CFG")" ]] || { echo "FAIL: second pass altered the config"; exit 1; }

# 4. A localised grub-mkconfig writes a different string. Leave it rather than
#    delete a line we did not recognise.
LOC="$TEST_ROOT/grub.fr.cfg"
cat > "$LOC" <<'EOF'
menuentry 'KOOMPI OS Linux' {
	echo	'Chargement de Linux linux ...'
	linux	/vmlinuz-linux root=UUID=deadbeef rw
}
EOF
loc_before="$(cat "$LOC")"
KOOMPI_GRUB_CFG="$LOC" quiet_grub_entries >/dev/null
[[ "$loc_before" == "$(cat "$LOC")" ]] || { echo "FAIL: touched a localised config"; exit 1; }

echo "ok test_grub_quiet.sh"
