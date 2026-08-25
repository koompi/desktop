# J43 report — the shell honours `koompi-notify-send --exec`

Branch `j43-notification-exec-hint`, from main at `a76a797b` (after J31). Files touched: `services/Notifications.qml`,
`modules/common/widgets/NotificationItem.qml`, `dots/.local/bin/koompi-notify-send` (consumer comment only), new
`tests/test_notification_exec_hint.sh`. `hints.rs` untouched; no `notificationHints.js` was needed.

## Which server the shell reads through
Quickshell's builtin `NotificationServer`, declared at `services/Notifications.qml:155-192` (`onNotification` wraps each
`Notification` in a `Notif`). The Rust service says so itself: `shell-services/notifications/src/lib.rs:4-5` ("`Notifications.qml`
declares Quickshell's builtin `NotificationServer`, which owns `org.freedesktop.Notifications` and does this work in C++").
Nothing under `dots/` references the Rust binary (only its own Cargo tree, tests and demo do), so `hints.rs:25-37` decoding
eleven keys is irrelevant to what the toast sees; the shell reads `notification.hints` (a `QVariantMap`) directly. J29 was right.

## What was built
- `Notif.execArgv` (`Notifications.qml:36-37`): `parseExecArgv(notification?.hints["koompi-exec-argv"])`. The hint arrives as
  the JSON string busctl sent (`s`); parse accepts only a non-empty array of strings, anything else (no hint, `""`, not JSON,
  an object, numbers in the array, `[]`) yields `[]`. Malformed logs one `console.warn` line; nothing throws.
- `execCommand(argv)` (`:79-81`): `["bash", "-lc", 'exec "$@"', "--"].concat(argv)`, the exact form the sender's contract names.
- `invokeExec(id)` (`:85-92`): finds the `Notif`, `Quickshell.execDetached(execCommand(execArgv))`, then `discardNotification(id)`
  like `attemptInvokeAction`. Returns false when the id is unknown or has no argv (so `invokeLast` can say `none`).
- `invokeLast` IPC (`:325-333`): freedesktop `default` action, else first action, else `invokeExec`; `none` only when neither exists.
- Click path (`NotificationItem.qml:20-23, 75-101`): both the toast and the history row are `NotificationGroup → NotificationItem`
  (`NotificationListView.qml:17-25`, `NotificationGroup.qml:250`), one path, so no third file. The item's `DragManager` now takes
  the left press when `hasExec` (`interactive: expanded || root.hasExec`; before, a collapsed item let it fall through to the
  group's expand `TapHandler`), and `onClicked` runs `Notifications.invokeExec` on a left button that was not a swipe
  (`dragged` is set in `onDraggingChanged`, cleared on press, so a swipe-to-dismiss never fires the command). Middle-click dismiss
  and drag-to-dismiss are unchanged; the cursor is a pointing hand over a row with an argv. Without `execArgv` nothing changes.
- Persistence: **dropped deliberately**. `notifToJSON` does not write `execArgv`, and the restore path (`:369-372`) creates the
  `Notif` with no `notification`, so the binding yields `[]`. Reason: the argv was for the toast it arrived on (open this
  screenshot, retry this migration step, restart the updater); running it days later from a restored history row is a surprise
  nobody clicked for, and it is the same reason `actions` are dropped there. Side benefit: no command line sits in
  `notifications.json`.
- `koompi-notify-send:18-20`: the comment now names the consumer and the IPC route.

## Test: `tests/test_notification_exec_hint.sh`
Static: exact `bash -lc 'exec "$@"' --` form, hint read, click path calls `invokeExec`, the fall-through fix, `invokeLast`
fallback, no `sh -c` in the service, sender names its consumer, both files ≤ 400. qmllint (Qt 6) on both. Probe: `qs -p` under
`dbus-run-session` (a private bus, so the live shell's `org.freedesktop.Notifications` is never contested), XDG dirs in a temp.
The probe sends a real `koompi-notify-send … --exec sh -c 'printf "%s\n" "$@" > "$0"' <out> "hi there" "--x"` and a raw busctl
`Notify` with `koompi-exec-argv s "not json"`, then checks `Notif.execArgv` deep-equals the argv, the malformed one is kept with
`[]` and logged, `notifToJSON` omits `execArgv`, `invokeExec` returns true and discards, and the file the real
`bash -lc 'exec "$@"' --` invocation wrote reads `"hi there\n--x\n"`. Skips (exit 0 with a `skip:` line) without qs,
dbus-run-session, busctl or jq.
Proof it fails: with `parseExecArgv` forced to `[]` → `FAIL parse keeps spaces and dashes  []`, `FAIL execCommand …`,
`FAIL Notif.execArgv is the argv koompi-notify-send encoded  []`, `PROBE FAILED 3`.

## Acceptance 1: test output and suite tail
```
$ nice -n 19 ionice -c 3 bash tests/test_notification_exec_hint.sh
ok   source: exact exec form, hint read, click path, invokeLast fallback, both files under 400 lines
ok   qmllint: Notifications.qml and NotificationItem.qml parse without errors
PASS parse keeps spaces and dashes  ["echo","hi there","--x"]
PASS malformed hints yield [] and never throw  [[],[],[],[],[],[],[],[]]
PASS execCommand is bash -lc 'exec "$@"' -- argv  ["bash","-lc","exec \"$@\"","--","echo","hi there","--x"]
PASS invokeExec on an unknown id is false
PASS both notifications arrived over the bus  seen=2
PASS Notif.execArgv is the argv koompi-notify-send encoded  ["sh","-c","printf \"%s\\n\" \"$@\" > \"$0\"","/home/userx/.tmp/tmp.7hosJESYMr/out.txt","hi there","--x"]
PASS a malformed hint keeps the notification with execArgv []
PASS execArgv is not persisted (notifToJSON omits it)
PASS invokeExec runs and discards
PASS the argv reached exec intact  "hi there\n--x\n"
PROBE OK
ok   probe: hint parsed over a real bus, argv preserved through bash -lc 'exec "$@"' --, malformed hint logged and dropped

$ shellcheck -x tests/test_notification_exec_hint.sh   # ok
```
`NO_COLOR=1 nice -n 19 ionice -c 3 ./tests/run.sh` tail (the same three skips as before; 83 → 84 passed, the +1 is this test):
```
==> test_zig_build_abort.sh
  ok test_zig_build_abort.sh

84 passed, 3 skipped, 0 failed
skipped: test_globalmenu.sh test_hypridle_logged.sh test_search_bench_parity.sh
rc=0
```

## Acceptance 2: live
**Unverified live.** `~/.config/quickshell/koompi` is a plain directory, not a link to this worktree, and the running shell
must not be reloaded from a job. The probe above is the stand-in: the same singleton, a real bus, a real `koompi-notify-send`,
and the real `bash -lc 'exec "$@"' --` run landing its argv in a file. After the next reload:
`koompi-notify-send -a test "click me" "runs touch /tmp/j43-clicked" --exec touch /tmp/j43-clicked`, click the body row of the
toast, `ls -l /tmp/j43-clicked`.

## Acceptance 3: lengths
`services/Notifications.qml` 394, `modules/common/widgets/NotificationItem.qml` 335 (both under 400).

## Follow-up the lead should know (not a stop: the shared path exists, the change is complete on it)
On a collapsed group the click target is the `NotificationItem` rows, i.e. the body line(s). A single-notification toast draws
its summary in the group's own title row (`NotificationGroup.qml:196-209`), which is outside the item, so a click on that title
still expands the group (expanded, the body row and its click run the argv). Making the title row run it too is one condition in
`NotificationGroup.qml`'s `TapHandler`/`toggleExpanded` (`:75-86`): when the group has one notification with `execArgv`, call
`Notifications.invokeExec`. That file is not in J43's ownership, so it is named here rather than changed.
