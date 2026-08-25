# J40 report — crash watch with a local diagnosis (O30)

Branch `j40-crash-watch`, commit `3cdbae42` (+ this report). Files: new `dots/.local/bin/koompi-crash-watch`,
`dots/.local/bin/koompi-crash-diagnose`, `dots/.config/systemd/user/koompi-crash-watch.service`, `docs/agents/crash.md`,
`tests/test_crash_watch.sh`; two `_tools` rows in `sdata/dist-arch/koompi-shell/PKGBUILD` (`pkgrel` untouched); one enable
block in `sdata/install/setups/system.sh` `setup_services` (J33 was already on main, so it is in, not reported).

## Findings that shaped the build

- **Do 1's permission question: no gap.** systemd 261's `systemd-coredump` runs its worker as the crashing user
  (`_UID=1000`, `COREDUMP_UID=1000`, `_SYSTEMD_UNIT=systemd-coredump@…`), so journald files this user's crash entries in
  `/var/log/journal/<mid>/user-1000.journal`, which carries `user:userx:r--`. Verified: `journalctl --file …/user-1000.journal
  MESSAGE_ID=… COREDUMP_UID=1000` returns them and `--file …/system.journal` returns none. Other users' and root's crashes are
  in `system.journal` (wheel/adm ACL) and are never announced anyway. So the follow is plain `journalctl --quiet` with
  `MESSAGE_ID=… COREDUMP_UID=$UID` matched in the journal; `--system` (my first cut) was wrong: it *misses* the user's own crashes.
- **"Local agent": neither Kiri nor the workbench.** `kiri --help` is a voice-to-text tool (voice, listen, dict, model…), no chat.
  `koompi-workbench` opens herdr, "terminal workspace manager for AI coding agents" (claude/codex/pi: cloud). The local model
  the tree actually has is LiteRT-LM on `127.0.0.1:9379` (socket-activated, the AI sidebar's engine; `ModelRegistry.qml:211`,
  `scripts/ai/show-installed-litert-lm-models.sh`). The diagnose asks it through `/v1/chat/completions` (streamed) in a
  terminal chosen the way `koompi-workbench:22-31` chooses one. That is the only address the tool knows; there is no flag to
  send the report elsewhere.
- **MESSAGE_ID fires without a core.** This machine has `Storage: none` entries ("terminated abnormally without generating a
  coredump"), 12+ of them from `/opt/MicroTeX/LaTeX` today (a crash loop in the MicroTeX renderer, SIGABRT, `session-3.scope`,
  from `~/.tmp/tmp.*/out/missing/*.svg` renders — someone's dev tree, not mine to touch; noting it for Rithy). The watcher
  announces those too, once a minute per program, which is the point.
- **Two bugs found by the real run and fixed before commit:** the EXIT trap named a function-local (`answer_file: unbound
  variable` after the answer), and `$(jq -r …)` per SSE chunk stripped every newline out of the model's answer. Now a global
  and `jq -j | tee`. A third from review: under `set -e`+`pipefail` a SIGPIPE on the `[DONE]` break or one unreadable chunk
  would have ended the script mid-answer; `|| true` on both.

## What was verified for real (this machine, no shims except the terminal window)

- `koompi-crash-diagnose 2641281 LaTeX /opt/MicroTeX/LaTeX SIGABRT` with `wezterm` shimmed to record argv: report written at
  `$XDG_STATE_HOME/koompi/crash/20260825-174619-LaTeX-2641281.md` (0600, dir 0700), real `coredumpctl info`, real journal
  query; wezterm argv `start -- <diagnose> --ask <report>`. Then `koompi-crash-diagnose --ask <report>` in this pane against
  the live `gemma4-e2b`: 43 s, a coherent four-point answer appended under `## Diagnosis (gemma4-e2b, …)`, rc 0. Also a
  pid-only hand run (`koompi-crash-diagnose 2641281`) fills comm/exe/signal from the info block.
- The unit was never enabled or started; no crash was triggered; no sudo.

## Acceptance 1 — test, packaged tools, suite tail, shellcheck

`nice -n 19 ionice -c 3 bash tests/test_crash_watch.sh`:
```
ok   follow: 7 entries -> 2 toasts (dedupe, ignore, other uid, own machinery, no pid), exact --exec argv
ok   dedupe: KOOMPI_CRASH_DEDUPE_SECONDS=0 announces the duplicate (3 toasts)
ok   ignore: the regex is the only thing keeping LaTeX quiet
ok   wait: no server -> nothing sent, stderr names the crash
ok   --once --dry-run: reads the newest entry, prints the argv, sends nothing
ok   diagnose: 0600 report with facts, coredumpctl info (read-only), both journal sections; no model -> Consented refusal toast, exit 3
ok   guards: bad pid 64 without a report, --ask without a model exits 1 naming the report
ok   unit: shape pinned, systemd-analyze --user verify clean
ok   setup_services: enables koompi-crash-watch (no --now), warns without a user manager
test rc=0
```

`tests/test_packaged_tools.sh`:
```
packaged tools: 31 shipped, 2 excluded, all accounted for
rc=0
```

`shellcheck -x dots/.local/bin/koompi-crash-watch dots/.local/bin/koompi-crash-diagnose tests/test_crash_watch.sh sdata/install/setups/system.sh`: empty, rc 0.

Suite (`NO_COLOR=1 nice -n 19 ionice -c 3 bash tests/run.sh`, tail):
```
  ok test_zig_build_abort.sh

87 passed, 3 skipped, 0 failed
skipped: test_globalmenu.sh test_hypridle_logged.sh test_search_bench_parity.sh
```
Baseline on this main is 86 (J33 left 85, J43 added `test_notification_exec_hint`); 87 = +1, the three skips are the known ones.

## Acceptance 2 — `koompi-crash-watch --once --dry-run` against the real journal

```
dry-run: would send: /home/userx/.herdr/worktrees/koompi-desktop/j40-crash-watch/dots/.local/bin/koompi-notify-send -a KOOMPI -u critical Process\ crashed:\ LaTeX SIGABRT.\ Click\ to\ diagnose\ with\ the\ local\ model. --exec /home/userx/.herdr/worktrees/koompi-desktop/j40-crash-watch/dots/.local/bin/koompi-crash-diagnose 2790199 LaTeX /opt/MicroTeX/LaTeX SIGABRT
rc=0
```
It read the newest entry filed under this uid, matched (`LaTeX`, not ignored), printed the argv, sent nothing and never touched
the bus. With `KOOMPI_CRASH_IGNORE='^LaTeX$'` the same command prints nothing, rc 0.

## Acceptance 3 — `journalctl -o json -n 1 MESSAGE_ID=fc2e22bc6ee647b6b90729ab34a250b1` as this user

rc 0, one 6529-byte line (no permission error). The whole line is mostly `COREDUMP_PROC_AUXV`/`COREDUMP_OPEN_FDS`; its fields
that matter, via `jq`:
```
{"__CURSOR":"s=20df23a9fd0247b5ae23b3445bb505dd;i=58ca82;b=8e9f6f41320c43aa9cc62a3f119b9fdb;m=72abc1cc5;t=659dcebce82ba;x=943e85dc2cd5acd4","MESSAGE":"Process 2790199 (LaTeX) of user 1000 terminated abnormally without generating a coredump.","_UID":"1000","COREDUMP_UID":"1000","COREDUMP_COMM":"LaTeX","COREDUMP_PID":"2790199","COREDUMP_EXE":"/opt/MicroTeX/LaTeX","COREDUMP_SIGNAL_NAME":"SIGABRT","COREDUMP_UNIT":"session-3.scope"}
```
First 300 bytes raw:
```
{"COREDUMP_OWNER_UID":"1000","_BOOT_ID":"8e9f6f41320c43aa9cc62a3f119b9fdb","__SEQNUM_ID":"20df23a9fd0247b5ae23b3445bb505dd","_SYSTEMD_INVOCATION_ID":"264e1425df0b4f8f8ad9fc4b9cf741c3","COREDUMP_UNIT":"session-3.scope","COREDUMP_PROC_MAPS":null,"_SOURCE_REALTIME_TIMESTAMP":"1787655244120592","COREDUM
```
`id`: `uid=1000(userx) … 998(wheel)`; but per the finding above wheel is not what makes this readable, the per-user journal ACL is.

## Not done / for Rithy

- `koompi-toggle crash-watch` (the off-switch writer) is J31's family, not built; the unit condition file is documented.
- The MicroTeX `LaTeX` SIGABRT loop in `session-3.scope` is real and ongoing on this machine (12+ entries today); once the
  unit is enabled it will toast once a minute until that renderer is fixed or `KOOMPI_CRASH_IGNORE` names it.
- A 2B model's reading is generic when the entry has no core (`Storage: none`, no stack); with a kept core the stack goes in.
