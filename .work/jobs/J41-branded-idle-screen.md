# J41 — Branded idle screen before lock (O32)

`.work/OMARCHY-AUDIT.md` row O32; the audit rejects omarchy's terminal/ASCII shape: ours is a Quickshell layer with the SVG mark.
Omarchy at `~/.tmp/omarchy`: `bin/omarchy-launch-screensaver`, `bin/omarchy-screensaver` (exit on any key or focus loss),
`default/omarchy/omarchy-menu.jsonc:121-123`. Shell root `Q=dots/.config/quickshell/koompi`. Read first: `dots/.config/hypr/hypridle.conf`
(29: lock at 300 s, DPMS 600 s, suspend 900 s; the "No idle dim" comment at :12-13 — an idle layer must not touch brightness),
`$Q/modules/koompi/cheatsheet/Cheatsheet.qml` (the model for a full-screen `WlrLayershell` panel gated on a `GlobalStates` bool),
`$Q/panelFamilies/KoompiFamily.qml:35-62` (registry), `$Q/GlobalStates.qml:12-36`, `$Q/modules/koompi/lock/Lock.qml` (lock-specific;
do not reuse), `$Q/assets/icons/koompi-symbolic.svg`, `$Q/services/Idle.qml` (keep-awake state, J31 owns it: read only),
`tests/test_hypridle_logged.sh:27-30` (no hand-started hypridle), `tests/test_qml_layering.sh:19-30`, `tests/test_keep_awake_lid.sh`.

## Files you own
- new `$Q/modules/koompi/screensaver/Screensaver.qml` (+ helpers under that directory, each ≤ 400)
- `$Q/panelFamilies/KoompiFamily.qml` (one `PanelLoader` line), `$Q/GlobalStates.qml` (one bool)
- `dots/.config/hypr/hypridle.conf` (one listener), `$Q/modules/common/Config.qml`? No — allow-listed at 827: the on/off and
  timeout live in `Persistent`? Also no. Decision: hypridle's listener is the only switch (comment it out = off); no Config key.
- `docs/navigation.md` (one row), new `tests/test_screensaver.sh`; `.work/J41-report.md`

## Do
1. `Screensaver.qml`: a `WlrLayershell` overlay on every screen, black with the KOOMPI mark drifting slowly (no burn-in: move
   every 20 s), the clock small in a corner, no brightness change, no keyboard grab beyond what dismissal needs. Opens via
   `IpcHandler` target `screensaver` (`open`/`close`/`toggle`) and closes on any key or pointer motion on it; also closes when
   `GlobalStates.screenLocked` turns on (the lock replaces it). If keep-awake is on (`Idle.inhibit`), hypridle never fires — no
   extra check needed; say so.
2. `hypridle.conf`: a listener at 120 s (`on-timeout = qs -c koompi ipc call screensaver open`, `on-resume = … close`), before the
   lock listener, with a comment; the lock at 300 s stays. Verify hypridle's `on-resume` fires on input while the layer is up.
3. `tests/test_screensaver.sh`: qmllint on the new files; static checks that `KoompiFamily.qml` loads it once, that
   `hypridle.conf` has the listener before the lock one, that no `brightnessctl`/`Brightness` reference exists in the new files
   (the :12-13 rule); `tests/test_qml_layering.sh` must still pass.

## Acceptance
1. Paste the test output, `test_qml_layering.sh`, `test_hypridle_logged.sh`, and the suite tail (baseline +1).
2. A headless capture (cage + nested qs, like J04) of the layer at `/tmp/j41-screensaver.png`. The live shell has not
   reloaded your QML, so the live `ipc call` is unverified until `koompi reload` — say so.
3. `hypridle` parses the new conf: run a throwaway `hypridle -c <copy>` with the 120 s listener shortened to 3 s ONLY if you
   also neutralise the lock/DPMS/suspend listeners in that copy (the lead did this in J15 safely); paste its log showing the
   `on-timeout` command running, then kill only that pid.

## Out of scope
- `Lock.qml`/`LockSurface.qml`, `Idle.qml`, brightness, DPMS timings, Settings UI for it (a later row).

## Stop conditions
- Never restart the live shell, never run a hypridle copy that can lock or suspend the session, never touch keep-awake.
