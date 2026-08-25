# Crash watch

`koompi-crash-watch` (`dots/.local/bin/koompi-crash-watch`, user unit
`dots/.config/systemd/user/koompi-crash-watch.service`) follows the journal for
systemd-coredump's entries and raises one critical toast per crashed program.
Clicking it runs `koompi-crash-diagnose`, which writes a report and asks the local
model about it. OMARCHY-AUDIT O30; the omarchy originals are
`bin/omarchy-crash-watch` and `bin/omarchy-agent-crash`.

## What the watcher captures

- Source: `journalctl --quiet --follow --lines=0 --output=json
  MESSAGE_ID=fc2e22bc6ee647b6b90729ab34a250b1 COREDUMP_UID=$UID`
  (`koompi-crash-watch:92-99`). The MESSAGE_ID is systemd-coredump's
  (systemd.journal-fields(7)); it is logged for every crash the handler saw, core
  kept or not (`Storage: none` entries included). Only this user's crashes match;
  a daemon's core is the sysadmin's.
- No privileges: systemd-coredump (261) runs its worker as the crashing user, so
  journald files the entry in `user-<uid>.journal`, which the user has an ACL on.
  The wheel/adm ACL on the system journal is not needed. `--lines=0` on the
  follow means a restart never re-announces a crash already dealt with.
- Read per entry: `COREDUMP_UID`, `COREDUMP_COMM`, `COREDUMP_PID`, `COREDUMP_EXE`,
  `COREDUMP_SIGNAL_NAME`. Nothing is stored; the watcher keeps one timestamp per
  program name in memory for the dedupe window.
- Filters, in order: numeric pid (an entry without one is logged and skipped),
  own uid, `KOOMPI_CRASH_IGNORE` (extended regex on the executable's basename, or
  the 15-char comm when there is no path), its own `koompi-crash-*` tools, and
  one toast per program per `KOOMPI_CRASH_DEDUPE_SECONDS` (60). Only a delivered
  toast starts the window, so a send that failed does not hide a crash loop.
- The toast waits up to `KOOMPI_CRASH_NOTIFY_WAIT` (30 s) for
  `org.freedesktop.Notifications` to have an owner (NameHasOwner, not a Notify
  probe, so nothing gets D-Bus-activated) because a shell crash is the one that
  takes the server down. Then `koompi-notify-send -a KOOMPI -u critical
  "Process crashed: <name>" "<signal>. Click to diagnose with the local model."
  --exec koompi-crash-diagnose <pid> <comm> <exe> <signal>`: four argv words,
  never a reparsed string (`koompi-notify-send`'s `koompi-exec-argv` hint).
- `koompi-crash-watch --once --dry-run` reads the newest matching entry and
  prints the argv it would send; nothing is sent and the bus is not touched.
- Off switch: the unit has
  `ConditionPathExists=!%h/.local/state/koompi/toggles/crash-watch-off`. Touch
  the file to keep the watcher off across logins; nothing writes it yet.

## What the diagnosis may read

`koompi-crash-diagnose <pid> [comm] [exe] [signal]` gathers, read-only:

- `coredumpctl info --no-pager <pid>` (the stack trace when a core was kept, the
  command line, unit, cgroup). A rotated-away entry costs only that section.
- `journalctl --no-pager --output=short-iso --lines=200 _COMM=<comm> + _PID=<pid>`:
  the process's own lines from both journals.
- When the entry names a user unit (a `koompi-launch` scope, a user service):
  `journalctl --user --lines=200 --unit=<user unit>`.

It writes them, under a fixed set of questions, to
`$XDG_STATE_HOME/koompi/crash/<date>-<name>-<pid>.md` (directory 0700, file
0600: the command line can carry file names and arguments). Then it opens a
terminal (the `koompi-workbench` order: wezterm, kitty, konsole, foot) running
`koompi-crash-diagnose --ask <report>`, which streams the model's answer and
appends it to the same file under `## Diagnosis`. The model sees the first
`KOOMPI_CRASH_PROMPT_BYTES` (24000) of the report and is told when it was cut.

## The consent rule

The model is LiteRT-LM on `127.0.0.1:$KOOMPI_LITERT_PORT` (9379), the engine
the AI sidebar serves from (`scripts/ai/show-installed-litert-lm-models.sh`),
asked through its OpenAI-compatible `/v1/chat/completions`; `KOOMPI_CRASH_MODEL`
picks a served model, the first listed otherwise. That is the only address the
tool knows. Kiri is voice-to-text, and herdr, which `koompi-workbench` opens,
fronts cloud coding agents, so neither is where a crash report goes.

When `GET /v1/models` on that port fails (no server, no model imported, the
machine below The Floor with local chat off), the report is still written and
the tool gives a Consented refusal (`CONTEXT.md`): a critical toast "No local
model to diagnose the crash of <name>" whose body names the report path and
whose click opens it with `xdg-open`; exit 3. It never routes the report to a
remote model, and there is no flag that would make it. The user reading the
report and choosing where to paste it is the only way its contents leave the
machine.
