# J43 — The shell honours `koompi-notify-send --exec` (a click runs the argv)

Serial after J31 (it owns `services/Notifications.qml` until it merges). Found by J29 (`.work/J29-report.md`, "Stop condition hit"):
`dots/.local/bin/koompi-notify-send:13-17,55-68` encodes the command as a JSON argv in the private `koompi-exec-argv` hint, and
nothing in the tree reads it — the migration toast (J29), the first-run fingerprint invitation (J37) and the crash toast (J40)
all rely on a click doing something. Shell root `Q=dots/.config/quickshell/koompi`. Read first: `koompi-notify-send` (the whole
file: the hint's contract and the required invocation `bash -lc 'exec "$@"' -- "${argv[@]}"`), `$Q/services/Notifications.qml`
(after J31: the `Notif` wrapper, `NotificationServer` at ~:155, `attemptInvokeAction` ~:243-256, the `notifications` IpcHandler),
`$Q/modules/common/widgets/NotificationItem.qml` (323; `MouseArea` at ~:72-77 handles middle-click dismiss only), the popup
widget under `$Q/modules/koompi/notificationPopup/`, `shell-services/notifications/src/hints.rs:25-37` (the Rust service decodes
eleven hint keys; find out whether the shell reads notifications through that service or through Quickshell's `NotificationServer`
— J29 says the latter; confirm and cite), `tests/test_services_qml_bugs.sh`, `tests/test_notify*.sh` if any (`ls tests | grep -i notif`).

## Files you own
- `$Q/services/Notifications.qml` (≤ 400: it is ~360 after J31 — if the hint parsing does not fit, put it in a new
  `$Q/services/notificationHints.js` and say so), `$Q/modules/common/widgets/NotificationItem.qml`
- `shell-services/notifications/src/hints.rs` only if the shell reads through it (then also its test module)
- `dots/.local/bin/koompi-notify-send` (only the comment naming the consumer, if it names none)
- new `tests/test_notification_exec_hint.sh`; `.work/J43-report.md`

## Do
1. Parse `hints["koompi-exec-argv"]` (JSON array of strings) into the `Notif` wrapper as `execArgv` (empty when absent or
   malformed; a malformed hint logs one line, never throws).
2. Left-click on a toast or a history row with `execArgv` runs it exactly as `koompi-notify-send` specifies — `["bash","-lc",
   'exec "$@"',"--", ...argv]` through `Quickshell.execDetached`, then dismisses the toast (like `attemptInvokeAction`). Without
   `execArgv`, left-click keeps today's behaviour. The `invokeLast` IPC (J31) prefers a freedesktop action and falls back to
   `execArgv` when there is none.
3. Persistence: `Notifications.qml` stores the list to disk (`FileView`, J-earlier); make sure `execArgv` round-trips or is
   dropped deliberately on restore (say which and why — running a stale argv after a shell restart is the risk).
4. `tests/test_notification_exec_hint.sh`: `notifToJSON`/parse probe with `qs -p` (skip line without `qs`) fed a hint
   `["echo","hi there","--x"]` proving the argv is preserved with spaces and dashes intact; qmllint on both files; a static check
   that the invocation is the exact `bash -lc 'exec "$@"' --` form.

## Acceptance
1. Paste the test output and the suite tail (baseline +1).
2. Live: `koompi-notify-send -a test "click me" "runs touch /tmp/j43-clicked" --exec touch /tmp/j43-clicked`, click the toast,
   `ls -l /tmp/j43-clicked` — only if the live shell has your QML (it will not until a reload): otherwise say unverified live
   and paste the probe.
3. `wc -l` of both QML files under 400.

## Out of scope
- `koompi-notify-send`'s flags, the Rust service beyond hint decoding, the sidebar layout.

## Stop conditions
- Never restart the live shell. If the popup/history widgets do not share one click path and the change would need a third
  file you do not own, stop and name it.
