# J40 — Crash watch that offers a diagnosis, local agent only (O30)

Serial after J31 (PKGBUILD `_tools`; leave `pkgrel` alone). `.work/OMARCHY-AUDIT.md` row O30. Omarchy at `~/.tmp/omarchy`:
`bin/omarchy-crash-watch` (journal `MESSAGE_ID=fc2e22bc6ee647b6b90729ab34a250b1`, per-program dedupe, ignore regex, waits for the
notification server, argv-safe `--exec`, `journalctl -f -n 0 -o json`), `bin/omarchy-agent-crash` (validates pid, builds the prompt),
`default/systemd/user/omarchy-crash-watch.service` (`ConditionPathExists=!…/toggles/crash-capture-off`, `Restart=always`).
Read first: `CONTEXT.md:31-36,96,101-107` (Consented refusal, never a Silent cloud fallback, Reduced-local mode),
`dots/.local/bin/koompi-litert-lm-watchdog:21` (the tree's `journalctl --follow --lines=0` idiom), `dots/.local/bin/koompi-workbench`
(opens the agent by hand), `dots/.local/bin/koompi-notify-send` (argv-safe `--exec`), `dots/.config/systemd/user/litert-lm-watchdog.service`
(unit shape), `dots/.config/hypr/custom/keybinds.lua:5-11` (Kiri, the local agent), `tests/test_hypridle_logged.sh` (unit static checks),
`tests/test_ai_request_privacy.sh`.

## Files you own
- new `dots/.local/bin/koompi-crash-watch`, new `dots/.local/bin/koompi-crash-diagnose` (+ `_tools` rows in `sdata/dist-arch/koompi-shell/PKGBUILD`)
- new `dots/.config/systemd/user/koompi-crash-watch.service`; one enable line in `sdata/install/setups/system.sh` `setup_services`
  (after J33 merges; until then report the line)
- `docs/agents/hooks.md`? No — new `docs/agents/crash.md` (what the watcher captures, what the diagnosis may read, the consent rule)
- new `tests/test_crash_watch.sh`; `.work/J40-report.md`

## Do
1. `koompi-crash-watch`: follows systemd-coredump entries (`journalctl --user`? No — coredumps are in the system journal; verify
   what an unprivileged user can read on Arch: `journalctl -o json MESSAGE_ID=…` needs `systemd-journal` group or `wheel`; if
   the seat user cannot read them, stop and report the exact gap before building), dedupes per `COREDUMP_COMM` for 60 s,
   honours `KOOMPI_CRASH_IGNORE`, waits for the notification server, then `koompi-notify-send -u critical --exec
   koompi-crash-diagnose <pid> <comm> <exe> <signal>` — argv words, no reparsed strings.
2. `koompi-crash-diagnose`: validates args, collects `coredumpctl info <pid>` (read-only), the last 200 journal lines for the
   unit/comm, and writes a prompt file under `$XDG_STATE_HOME/koompi/crash/`; then opens the **local** agent (Kiri, or the
   workbench with the local model — pick what `koompi-workbench` does and cite). If no local agent is available: a
   Consented-refusal notification ("no local model; open the report yourself at …"), never a cloud call.
3. The unit: `PartOf=graphical-session.target`, `Restart=on-failure`, `ConditionPathExists=!%h/.local/state/koompi/toggles/crash-watch-off`
   (the `koompi-toggle` family from J31 can grow a `crash-watch` thing later; not yours).
4. `tests/test_crash_watch.sh`: shims `journalctl` (emits two fixture JSON lines, one duplicate), `busctl`, `koompi-notify-send`,
   `coredumpctl`; proves dedupe, ignore regex, the exact `--exec` argv, the diagnose prompt file contents, and the no-local-agent
   refusal path; `systemd-analyze --user verify` on the unit.

## Acceptance
1. Paste the test output, `test_packaged_tools.sh`, and the suite tail (baseline +1). `shellcheck -x`: empty.
2. `koompi-crash-watch --once --dry-run` (add it) on this machine against the real journal: paste — it reads, matches, sends nothing.
3. `journalctl -o json -n 1 MESSAGE_ID=fc2e22bc6ee647b6b90729ab34a250b1` as this user: paste the first line or the permission error (that decides Do 1).

## Out of scope
- Any remote AI, the AI sidebar, `koompi-workbench` itself, `FeedbackService`.

## Stop conditions
- Never enable/start the unit here; never trigger a crash to test (no `kill -SEGV` on anything Rithy runs — a throwaway
  `sleep` you started yourself is fine, say so). No sudo.
