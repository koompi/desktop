# J20 — the lock screen unlocks itself ~2.6 s after locking (critical)

Found by J15 (`.work/J15-report.md`, "Findings outside my files"), reproduced three times there:
`hyprctl dispatch 'hl.dsp.global("quickshell:lock")'` → session locked → unlocked after 2.57-2.60 s with nobody
touching the reader or keyboard. Journal on every lock: `qs[<pid>]: PAM _pam_init_handlers: no default config
other` then `fprintd.service: Deactivated successfully`. Three fingerprints are enrolled (`fprintd-list`). The only
unlock path is `LockScreen.qml:41` after a PamContext success; `LockContext.qml` runs a password `pam` and a
`fingerPam` with `configDirectory: "pam"`, `config: "fprintd.conf"` (`modules/common/panels/lock/pam/fprintd.conf`
= `auth sufficient pam_fprintd.so`). Hypothesis to test first: with `_pam_init_handlers` failing to load the
config, PAM falls through to the `other` stack; on Arch `/etc/pam.d/other` is `pam_deny`... unless the fingerprint
PamContext resolves a path where a `sufficient`-only stack with no failing line ends in success. Find out, do not
guess. Lid lock, `Super+L`, the session menu and the idle lock are all cosmetic until this is fixed.

## Files you own
- `dots/.config/quickshell/koompi/modules/koompi/lock/LockContext.qml`, `LockScreen.qml`, `LockSurface.qml`, `Lock.qml`
- `dots/.config/quickshell/koompi/modules/common/panels/lock/pam/` (both files)
- `services/Idle.qml` only for the `alsoInhibitIdle` side effect J15 saw (keep-awake flipped on by the auto-unlock)
- new `tests/test_lock_pam.sh`; `.work/J20-report.md`

## Do
1. Reproduce once, timed, exactly as J15 did (journal + hypridle log). Warn in the report that reproducing locks
   Rithy's live session for ~3 s each time; keep reproductions to the minimum.
2. Establish the real mechanism with evidence: `pamtester`-style or a `qs -p` probe of PamContext with the same
   config dir, the journal lines with `SYSTEMD_LOG_LEVEL=debug` on fprintd if needed, `strace -e openat` on the
   PAM config lookup if strace is available (it is not; say so if you needed it). Name the PAM stack that returned
   success and why.
3. Fix at the root: a config PAM actually loads (absolute `configDirectory`? file name? `pam_fprintd` needs
   `auth required pam_deny.so` after a `sufficient` line so an unloaded module never falls to success), and the
   shell must treat a PamContext *error* (config not found, module missing) as failure, never as unlock.
4. Test: `tests/test_lock_pam.sh` — a probe that runs the fingerprint PamContext against a directory whose config is
   missing/unloadable and asserts the result is failure, not success; plus the password stack still succeeds with the
   right password against `pamtester`-equivalent or a `qs -p` probe if that is possible without a real password
   (document what could not be automated).
5. After the fix: lock via `hyprctl dispatch 'hl.dsp.global("quickshell:lock")'`, wait 30 s, confirm still locked
   (`loginctl show-session -p LockedHint`), unlock with the password yourself is NOT possible for you — say so; ask
   the lead to unlock and note the time in the report. Fingerprint unlock must still work afterwards (lead verifies).

## Acceptance
1. Paste the reproduction (before) with timestamps and the journal lines.
2. Paste the mechanism evidence and one paragraph naming it.
3. Paste the test failing against the old config/logic and passing after.
4. Paste `loginctl show-session -p LockedHint` at 0 s and 30 s after locking with the fix.
5. `./tests/run.sh` tail; `qmllint` delta on touched QML.

## Out of scope
- Hyprlock fallback, hypridle timings, J15's third finding (login-time hypridle ignoring Lock) — report only.

## Stop conditions
- Never weaken the stack (no `pam_permit`, no removing the password path). If the only fix you can find loosens
  security, stop and report.
- Do not enrol/delete fingerprints; do not touch `/etc/pam.d` (needs sudo; propose the change in the report).
- Never `pkill`/`killall` by name; never touch `~/.config/koompi/config.json`.
