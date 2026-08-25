# J37 report — fingerprint enrolment wizard, invited on first run when a reader exists (O15)

Branch `j37-fingerprint-enrolment`, commit `6cb54ab0` (feature) plus this report.
Files: new `dots/.local/bin/koompi-hw-fingerprint` (78 lines), new `dots/.local/bin/koompi-setup-fingerprint` (199),
`dots/.local/bin/koompi-lid` (+`--closed`, 57; I own it too, see Do 2), `koompi-shell/PKGBUILD` (two `_tools` rows, `pkgrel` untouched),
`pam/fprintd.conf` (comment only, still two auth lines), `services/FirstRunExperience.qml` (+4), `modules/settings/interface/LockScreenSection.qml` (114 → 172),
new `tests/test_fingerprint_setup.sh` (265).
`test_lock_pam.sh` and `test_first_run_wallpaper.sh` needed no change: the auth-line count is still 2, and the `handleFirstRun` pin (guard before switch, welcome after switch) holds with the new line last in the body.
`LockContext.qml` lives at `modules/common/panels/lock/`, as J20 found; `LockSurface.qml`, `LockContext.qml`, `/etc/pam.d` and `koompi-basic/PKGBUILD` untouched.

## Do 1 — `koompi-hw-fingerprint`

Port of `~/.tmp/omarchy/bin/omarchy-hw-fingerprint`: sysfs only, vendor list `27c6 138a 06cb 08ff 1c7a 147e`, product-string match (`*fingerprint*`, `*biometric*`, `*elan:arm-m4*`, `fpc *`), and the vendor path counts only when no interface has a kernel driver other than usbfs (libfprint drives readers from userspace; the same vendors ship webcam bridges and touchpads that bind one).
`--verbose` names the device and the rule; without it the tool is silent both ways.
`KOOMPI_USB_DEVICES_PATH` redirects the scan for the test.
No fprintd dependency.

## Do 2 — `koompi-setup-fingerprint` and the gate

`fprintd-enroll -f <finger> $USER` (default `right-index-finger`, `--finger` overrides; fprintd's policy `net.reactivated.fprint.device.enroll` is `auth_self_keep` on this machine, so no sudo for the enrolment itself).
Then y/N for sudo and y/N for polkit; each edit is `sudo sed -i` inserting

```
auth      [success=1 default=ignore]  pam_exec.so quiet /usr/bin/koompi-lid --closed
auth      sufficient                  pam_fprintd.so
```

above the stack's first `auth` line.
Idempotent by `grep` before `sed`; three shapes handled and tested: both present (no-op), pam_fprintd present without the gate (this machine's sudo: the gate goes directly above the existing line, which is kept), gate present without its module (stale gate dropped, both re-inserted once).
A stack with no `auth` line at all is left alone and reported, exit 1.
polkit: Arch's polkit ships `/usr/lib/pam.d/polkit-1` (pam's vendor dir; `/etc/pam.d/polkit-1` is absent here) and a file in `/etc/pam.d` replaces it whole, so the script `sudo install`s a copy of the vendor file first and edits that, instead of omarchy's hand-written `pam_unix` stanza.

Clamshell predicate: `koompi-lid` exposed no lid-state query (only the `close|open` bind handlers, whose predicate is the external-monitor check), so it now has `--closed`: exit 0 when any `/proc/acpi/button/lid/*/state` says closed, 1 otherwise, including a machine without a lid switch.
It reads procfs, not hyprctl, because pam_exec runs as root inside sudo and polkit-agent-helper-1 with no compositor socket.
I own `koompi-lid` for that hunk (+16 lines; the `close`/`open` paths untouched).
The path in the gate is `/usr/bin` because pam_exec expands nothing and that is where koompi-shell installs the tool; where it is absent pam_exec fails and `default=ignore` falls through to pam_fprintd, i.e. no gate.

Lock screen: **no gate**; `fprintd.conf` keeps its two auth lines and a comment records the decision.
Reasoning, cited:

- `LockContext.qml:85-120` (`tryUnlock`) and `:103-112` (`tryFingerUnlock`) are two independent PamContexts; the password one never waits on the fingerprint one.
  J20 measured exactly that live (`.work/J20-report.md`, Do 5): Rithy's password unlock landed at 13:27:26.7, 15.7 s into a 30 s fingerprint arm, and fprintd's `verify-no-match` there was the `VerifyStop` the password success triggered.
  So a shut lid with an external monitor costs the password path nothing today; for latency the gate is moot.
- It would be worse than moot: with the gate, a shut lid makes the stack `pam_exec` → skip → `pam_deny` → `Failed` in milliseconds, and `LockContext.qml:328-332` answers `Failed` with the "not recognized" state and `fingerprintRearmTimer` (`:338-345`, 1.5 s), so the lock would spawn `koompi-lid` and flash the failed state every 1.5 s for as long as the lid stayed shut.
  Fixing that means touching `LockContext`, out of scope.
- What the lock does today with the lid shut is the same as with nobody at the reader: one 30 s timeout and a quiet re-arm every 31.5 s (J20's journal cadence).

## Do 3 — first-run invitation

`handleFirstRun()` gains one line, `Quickshell.execDetached(["koompi-setup-fingerprint", "--invite"])`, after the welcome guide.
`--invite` exits 0 silently unless `koompi-hw-fingerprint` succeeds, `fprintd-enroll` is installed and `fprintd-list $USER` lists no ` - #` row; then it waits up to 30 s for the shell's NotificationServer to own `org.freedesktop.Notifications` (a first run races it; `migrate-lib.sh` waits the same way) and sends one `koompi-notify-send -u critical … --exec <self> --terminal` (critical as omarchy's hook sends it, so it does not time out unseen).
Once only: the marker file gates `handleFirstRun`.
The click runs `koompi-setup-fingerprint --terminal`, which opens the first terminal found in `variables.lua`'s order with that terminal's own run-a-command spelling (the table from `migrate-lib.sh`'s `terminal_argv`: `wezterm start --`, `foot`, `kitty -1`, `kgx --`, else `-e`) running the setup with `--hold`, which waits for Enter before the window closes, on error too.

## Do 4 — Settings

`LockScreenSection.qml`: the "If you want to somehow use fingerprint unlock..." tooltip is gone.
A "Fingerprint" subsection runs `koompi-hw-fingerprint` (exit code → reader present) and `fprintd-list "$(id -un)"` (count of ` - #` rows) at load, shows "Looking… / No fingerprint reader found / reader found; no finger enrolled yet / fingers enrolled: N", and an "Enrol fingerprint" button, enabled only with a reader, runs `koompi-setup-fingerprint --terminal`.
Not exercised live: the probes would be harmless, but the button starts a real enrolment, which the Stop condition forbids; qmllint only.

## Do 5 — test

`tests/test_fingerprint_setup.sh`: fake sysfs for the detector (no reader → exit 1 silent; `06cb`+usbhid no; `06cb:0123` with no driver yes and `--verbose` names it; usbfs yes; `ELAN:ARM-M4` and `Goodix Fingerprint USB Device` yes; bad flag 64), a fake ACPI dir for `--closed`, then the setup with `fprintd-enroll`, `fprintd-list`, `sudo` (logs argv, `exec "$@"`), `busctl`, `koompi-notify-send` and `wezterm` shimmed on PATH and PAM files under `KOOMPI_PAM_ROOT`: no reader → exit 1 with a reason and no calls; `--invite` silent with no reader or with a print, one `--exec … --terminal` critical toast otherwise; `--terminal` argv; decline both → no sudo, files untouched; failed enrolment → exit 1 before any prompt; accept both → gate directly above pam_fprintd, both above the original `include system-auth`, header kept, polkit-1 copied from the vendor file through sudo; second run byte-identical; the hand-written and stale-gate shapes; the no-auth-line refusal; the two QML pins; qmllint on both QML files.
Proof it can fail: swapping the gate and module in the sed → `FAIL: …/sudo: first auth line is not the clamshell gate: 2:auth sufficient pam_fprintd.so` (and two more).

## Acceptance 1 — test outputs (all under `nice -n 19 ionice -c 3`)

```
$ bash tests/test_fingerprint_setup.sh
ok   koompi-hw-fingerprint: silent exit 1 with no reader; vendor, driver, usbfs and product-string rules
ok   koompi-lid --closed: 0 closed, 1 open, 1 without a lid switch
ok   --invite: silent without a reader or with a print enrolled; one --exec toast otherwise
ok   --terminal: wezterm start -- <self> --hold, the finger carried along
ok   setup: enrol for $USER with --finger, y/N per stack, gate directly above pam_fprintd, idempotent, polkit-1 from the vendor file
ok   shell: first run invites once, settings probe the reader and launch the setup in a terminal
ok   qmllint: FirstRunExperience and LockScreenSection parse without errors
fingerprint setup: all checks passed
rc=0

$ bash tests/test_lock_pam.sh
ok   pam/: fprintd.conf is sufficient pam_fprintd + required pam_deny; other denies all four types
ok   LockContext: unlock gated on PamResult.Success twice, start() failures handled; LockScreen sets LockedHint
ok   missing config: start() is false and nothing completes
ok   shipped stack with an unloadable pam_fprintd: completes without success (completed=1)
ok   sufficient-only stack with an unloadable module: libpam's own fallback also denies (completed=2)
ok   positive control: the probe reports success when libpam grants it
ok   journal: only the directory without 'other' logged '_pam_init_handlers: no default config other'
rc=0

$ bash tests/test_first_run_wallpaper.sh
ok
rc=0

$ bash tests/test_packaged_tools.sh
packaged tools: 31 shipped, 2 excluded, all accounted for
rc=0

$ ./tests/run.sh   (tail)
==> test_zig_build_abort.sh
  ok test_zig_build_abort.sh

86 passed, 4 skipped, 0 failed
skipped: test_ai_e2e.sh test_globalmenu.sh test_hypridle_logged.sh test_search_bench_parity.sh
suite rc=0
```

## Acceptance 2 — this machine

```
$ koompi-hw-fingerprint --verbose; echo $?
koompi-hw-fingerprint: /sys/bus/usb/devices/3-5.4: vendor 06cb:0123 ships fingerprint readers and no kernel driver is bound to it
0
$ koompi-hw-fingerprint; echo $?      (silent)
0
$ koompi-lid --closed; echo $?         (lid open)
1
```

The reader (Synaptics 06cb:0123, J20's "press" sensor) has no `product` string in sysfs and its one interface has no driver, so it is the vendor rule that finds it; `3-4` (SunplusIT camera, uvcvideo) and the hubs do not match.

## Acceptance 3

`shellcheck -x dots/.local/bin/koompi-hw-fingerprint dots/.local/bin/koompi-setup-fingerprint dots/.local/bin/koompi-lid tests/test_fingerprint_setup.sh`: empty.
`wc -l`: koompi-hw-fingerprint 78, koompi-setup-fingerprint 199, koompi-lid 57, LockScreenSection.qml 172, FirstRunExperience.qml 52; caps 400.
`test_file_length.sh`: `ok: 913 files under cap, 34 allow-listed and not grown`.
qmllint (Qt 6): no errors in either QML file; the warnings are the "Unqualified access" and import classes both files had before, plus the same class on the lines I added.

## Stop conditions

No `fprintd-enroll`, `fprintd-delete`, sudo or PAM edit ran on this machine; `fprintd-list userx` (read-only) still shows the one `right-index-finger`.
`handleFirstRun()` took its step without touching `test_first_run_wallpaper.sh`.

## Not done, reported

- The enrolment flow end to end (a real `fprintd-enroll`, a real `sudo sed`) is unverified by construction; the shims prove the argv and the file edits.
  Rithy can exercise it with `koompi-setup-fingerprint --finger left-index-finger` in a terminal and answer N twice to keep `/etc/pam.d` as it is.
- This machine's `/etc/pam.d/sudo` already carries `pam_fprintd` without the gate; a `y` on the sudo prompt would add the gate above it (the tested shape).
- `docs/navigation.md` has no rows for the two tools (J31 added rows for its tool; the file is not in my list).
