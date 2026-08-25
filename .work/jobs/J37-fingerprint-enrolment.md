# J37 — Fingerprint enrolment wizard, invited on first run when a reader exists (O15)

Serial after J31 (PKGBUILD `_tools`; leave `pkgrel` alone — the lead bumps it). `.work/OMARCHY-AUDIT.md` row O15. Omarchy at
`~/.tmp/omarchy`: `bin/omarchy-hw-fingerprint` (sysfs vendor + product-string detection, no fprintd needed),
`bin/omarchy-setup-security-fingerprint` (enrol, then `pam_fprintd` into sudo + polkit with a clamshell gate
`auth [success=1 default=ignore] pam_exec.so quiet /usr/bin/omarchy-hw-laptop-closed` before it), `install/user/first-run/setup-fingerprint.hook`.
Shell root `Q=dots/.config/quickshell/koompi`. Read first: `$Q/modules/common/panels/lock/pam/fprintd.conf` (9 lines; J20 hardened it),
`$Q/modules/koompi/lock/LockContext.qml:246-257` (`fprintd-list` probe → `fingerprintsConfigured`), `$Q/services/FirstRunExperience.qml`
(48: `handleFirstRun()` is two hard-coded actions), `$Q/modules/settings/interface/LockScreenSection.qml:19` (placeholder text),
`tests/test_lock_pam.sh:22-36` (exactly two `auth` lines in `fprintd.conf`), `tests/test_first_run_wallpaper.sh:19-25` (pins
`handleFirstRun`'s body), `dots/.local/bin/koompi-lid:20-25` (the internal-panel predicate), `.work/J20-report.md`.

## Files you own
- new `dots/.local/bin/koompi-hw-fingerprint`, new `dots/.local/bin/koompi-setup-fingerprint` (+ `_tools` rows in
  `sdata/dist-arch/koompi-shell/PKGBUILD`)
- `$Q/modules/common/panels/lock/pam/fprintd.conf`, `$Q/services/FirstRunExperience.qml`, `$Q/modules/settings/interface/LockScreenSection.qml`
- `tests/test_lock_pam.sh` (the auth-line assertion only), `tests/test_first_run_wallpaper.sh` (only if the body pin breaks),
  new `tests/test_fingerprint_setup.sh`; `.work/J37-report.md`

## Do
1. `koompi-hw-fingerprint`: exit 0 when a reader exists, sysfs only (port omarchy's vendor list and product-string match; cite),
   `--verbose` prints what matched. No fprintd dependency.
2. `koompi-setup-fingerprint`: interactive: `fprintd-enroll` for the current user (right index by default; `--finger` option),
   then offers (y/N each) `pam_fprintd` for `sudo` and `polkit-1` via sudo, idempotent seds, with the clamshell gate line —
   our predicate is `koompi-lid`'s panel check, not omarchy's; find whether `koompi-lid` exposes "lid closed" as an exit
   status; if not, add a `--closed` query to it (then you own `koompi-lid` too, say so). Lock screen needs nothing: J20's
   `fprintd.conf` already allows it — decide whether the lock also gets the gate (a shut lid with an external monitor
   should not wait on the reader; J20 chose parallel fingerprint+password, so the gate may be moot: measure, decide, cite).
3. First-run invitation: `FirstRunExperience.handleFirstRun()` gains one step: if `koompi-hw-fingerprint` succeeds and
   `fprintd-list` shows none, a `koompi-notify-send --exec` toast opens a terminal running `koompi-setup-fingerprint`
   (terminal from `variables.lua`). Once only (the first-run marker already exists).
4. Settings: `LockScreenSection.qml` replaces the placeholder with the reader state and an "Enrol fingerprint" button that
   launches the same setup in a terminal.
5. Tests: `test_fingerprint_setup.sh` shims `fprintd-enroll`, `fprintd-list`, `sudo`, `sed`-target files under a temp root
   (`KOOMPI_PAM_ROOT` env) and proves: no reader → exit 1 silent; enrol then both PAM edits idempotent; gate line precedes
   `pam_fprintd`; qmllint on the two QML files. Update `test_lock_pam.sh`'s line count only if you changed `fprintd.conf`.

## Acceptance
1. Paste the new test, `test_lock_pam.sh`, `test_first_run_wallpaper.sh`, `test_packaged_tools.sh`, and the suite tail.
2. `koompi-hw-fingerprint --verbose; echo $?` on this machine (it has a reader: J20 found real verify-match events).
3. `shellcheck -x` on the scripts: empty. `wc -l` under cap.

## Out of scope
- `LockSurface.qml` (734, allow-listed), `LockContext.qml`, `/etc/pam.d` on this machine, `koompi-basic/PKGBUILD` (fprintd is there).

## Stop conditions
- Never run `fprintd-enroll`, `fprintd-delete`, or any sudo/PAM edit on this machine; shims only. Rithy's fingerprints stay as they are.
- If `handleFirstRun()` cannot take a step without breaking `test_first_run_wallpaper.sh`'s pin in a way that weakens it, stop and report.
