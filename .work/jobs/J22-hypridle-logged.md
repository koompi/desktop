# J22 — hypridle runs with its output on /dev/null; log it so lock handling is provable

From J15 (`.work/J15-report.md`, finding 3): the login-time hypridle (pid 2336 that session) is started by
`dots/.config/hypr/hyprland/execs.lua:17` with stdout/stderr on `/dev/null`, so whether it honours logind `Lock`
("Got Lock from dbus") cannot be shown from a log. J15 could only prove the lock path with a hypridle it started
by hand. Until this is fixed, "lid close locks" and the idle lock are unverifiable at a real login.

## Files you own
- `dots/.config/hypr/hyprland/execs.lua` (the hypridle line only)
- `dots/.config/systemd/user/hypridle.service` if you choose the unit route (new), and its enable step in `sdata/install/setups.sh` `setup_services` (that function only)
- `dots/.config/hypr/hypridle.conf` only if the unit route needs a path change
- new `tests/test_hypridle_logged.sh`; `.work/J22-report.md`

## Do
1. Pick one: (a) keep the exec in `execs.lua` but route output to the journal (`systemd-cat -t hypridle hypridle`), or (b) run the packaged `hypridle.service` user unit (Arch ships `/usr/lib/systemd/user/hypridle.service`, `PartOf=graphical-session.target`) and drop the exec. Say which and why; (b) is preferred if `graphical-session.target` is reached in the KOOMPI session (`systemctl --user is-active graphical-session.target`), because a unit restarts on crash and one hypridle can never become two on `hyprctl reload` (check whether that happens today: `pgrep -c hypridle` before and after `hyprctl reload`).
2. Make sure exactly one hypridle runs after login and after `hyprctl reload`; kill only the pids you started while testing.
3. Prove the lock path at a real login: `journalctl --user -t hypridle -b` (or the unit log) must show `Got Lock from dbus` after `loginctl lock-session`. If the login-time instance ignores Lock (J15 suspected it), find out why (D-Bus session bus env at exec time?) and fix that too; that is the actual bug behind this job.
4. Test: the exec/unit exists, output is not `/dev/null`, and a `loginctl lock-session` in a session produces the journal line within 2 s (skip honestly outside a session).

## Acceptance
1. Paste `pgrep -a hypridle` before/after `hyprctl reload`: one instance both times.
2. Paste the journal lines for a `loginctl lock-session` from the login-time instance (needs a fresh login: ask the lead to do the login and paste; say so if not done).
3. `./tests/run.sh` tail on the merged tree; `luac5.4 -p execs.lua`.

## Out of scope
- Lock screen logic (J20), hypridle timeouts, hyprlock.

## Stop conditions
- Never kill by name. Do not log out or reboot the machine; ask the lead.
