# J18 — Quickshell services bugs: report

Branch `j18-shell-services-bugs`, 14 fix commits + 1 test commit on top of `b5594362`.
Only files under `services/` named in the job and `tests/test_services_qml_bugs.sh` were touched.
Runtime checks ran with `qs -p` probes against a symlinked shell root, `XDG_*` in a temp dir, and PATH shims; nothing read or wrote `~/.config/koompi/config.json`, the clipboard database, the keyring, or the user's audio.

qmllint: `/usr/bin/qmllint` is Qt 5 and exits 255 silently on `list<var>` / `pragma ComponentBehavior`; every count below is `/usr/lib/qt6/bin/qmllint -I <dir with qs -> shell root> -I /usr/lib/qt6/qml`.
No touched file is warning-free before or after (pre-existing `[import]`, `[unqualified]`, `[missing-property]` across the tree); the table gives before → after so the delta is visible.

| file | before | after |
|---|---|---|
| MemoryService | 5 | 5 |
| Notifications | 12 | 12 |
| LauncherSearch | 7 | 7 |
| HyprlandXkb | 2 | 2 |
| Wallpapers | 38 | 38 |
| Cliphist | 16 | 16 |
| Emojis | 11 | 9 (two `missing-property` gone) |
| Privacy | 2 | 2 |
| Ai | 171 | 171 |
| Updates | 17 | 18 (one `signal-handler-parameters` on the new `onExited`, same as the file's other handler) |
| MprisController | 13 | 13 |
| Audio | 18 | 18 |
| EasyEffects | 4 | 4 |
| LatexRenderer | 11 | 7 |

## H7 — memory daemon gets an empty embedding key

Verdict: **confirmed**.
`ModelRegistry.qml:385` writes `KeyringStorage.setNestedField(["apiKeys", model.key_id], key.trim())`, a string; `Requester.qml:141` and `Conversation.qml:610` read `apiKeys[model.key_id]` directly. `MemoryService.qml:46` read `?.[id]?.key`, undefined on a string.

Changed: `KeyringStorage.keyringData?.apiKeys?.[id] ?? ""` (commit `fix(memory)`).

Check (probe, in the test):
```
PASS H7 apiKeys.<id> is the key string  the old ?.key read yields empty
```
i.e. `({apiKeys:{gemini:"sk-test"}})?.apiKeys?.["gemini"]?.key ?? ""` → `""`, without `?.key` → `"sk-test"`.

## M6 — timer laps / tray pins never persist (in-place push)

Verdict: **not a bug** on the shipped Qt (6.11.2).
Both properties are `list<var>` (`Persistent.qml:165`, `Config.qml:629`); Qt 6 sequence properties write back on `push`, which emits the change signal, which JsonAdapter turns into `adapterUpdated`.
Reproduction (FileView + JsonAdapter with the same nesting, `states.timer.stopwatch.laps.push(123)` and `states.tray.pinnedItems.push("Blueman")`):
```
M6 adapterUpdates after push: 2 laps=[123] pins=["Fcitx","Blueman"]
--- states.json
{ "timer": { "stopwatch": { "laps": [ 123 ], "running": false } },
  "tray": { "pinnedItems": [ "Fcitx", "Blueman" ] } }
```
The `LaunchpadUsage.qml:35` convention comment is about `var` objects (`counts`, `lastUsed`), where in-place mutation really is invisible; it does not apply to typed lists.
`TimerService.qml` and `TrayService.qml` untouched.

## M7 — notification timeout timer on a dismissed popup

Verdict: **confirmed**.
`discardNotification` (`:197`) splices the list and never stops the entry's timer; when it fires, `root.list[-1]` is undefined and `notifObject.isTransient` throws before `destroy()`.

Changed: `if (!notifObject) { destroy(); return; }` after the lookup (commit `fix(notifications)`).

Check: the runtime path needs a NotificationServer on the session bus, which the running shell owns, so the guard is pinned at source (`grep 'if (!notifObject) {'` in the test) and the failure mode is reproduced as the handler's own JS under `qs -p`:
```
const list = []; const index = list.findIndex(n => n.notificationId === 1); const notifObject = list[index];
try { if (notifObject.isTransient) …; console.log("destroy() reached"); } catch (e) { console.log("thrown before destroy(): " + e); }
→ thrown before destroy(): TypeError: Cannot read property 'isTransient' of undefined
```

## M8 — launcher runs prefixed sudo commands without a terminal

Verdict: **confirmed**.
`LauncherSearch.qml:427` tested `root.query.startsWith('sudo')`; with `search.prefix.shellCommand` (`"$"`, `Config.qml:653`) typed, the query starts with `$`.

Changed: `cleanedCommand.trim().startsWith('sudo')` (commit `fix(launcher)`); `trim()` because `"$ sudo …"` leaves a leading space after `cleanPrefix`.

Check (probe, `StringUtils.cleanPrefix` from the tree):
```
PASS M8 prefixed sudo is detected on the cleaned command
```
(`"$sudo pacman -Syu".startsWith("sudo")` is false; `cleanPrefix(...,"$").trim().startsWith("sudo")` is true.)

## M13 — xkb layout+variant concatenated without separator

Verdict: **mechanism in the row is wrong, failure is real**.
base.lst variant lines carry the colon: `  intl            us: English (US, intl., with dead keys)` (`/usr/share/X11/xkb/rules/base.lst:422`), so `matchVariant[2] + matchVariant[1]` is `us:intl`, not `usintl`.
`HyprlandXkbIndicator.qml:14` splits on `:` and stacks the parts, so the bar rendering is by design, not garbage.
What does fail: `layoutCodes` came from hyprctl's plain `layout` field (`us,kh`), so `InputConfig.qml:90,98` never matched `us:intl` and Settings never highlighted the active layout when a variant is set.

Changed: `layoutCodes` is built from `layout` and `variant` together in the same `code:variant` form (commit `fix(xkb)`). `InputConfig.qml` and the indicator are not mine and need no change.

Check (shimmed `hyprctl` returning `layout "us,kh"`, `variant "intl,"`, real base.lst):
```
PASS M13 layoutCodes carry the variant as base.lst does  ["us:intl","kh"]
PASS M13 the active variant layout matches an entry  us:intl
```

## M14 — wallpaper browser applies invalid directories

Verdict: **confirmed** by reading `Wallpapers.qml:95-102`: assignment before the result check, empty `dir` branch.

Changed: assignment moved into the `result === "dir"` branch (commit `fix(wallpapers)`).

Check (probe):
```
PASS M14 invalid directory left the folder alone  /home/userx/Pictures/Wallpapers
PASS M14 valid directory applied  /home/userx/.tmp/tmp.XDJ1CbkLtu/out
```

## M16 — clipboard delete drops rapid second deletions

Verdict: **confirmed, and worse than the row says**.
Quickshell starts a `Process` on the event loop, not inside `running = true`; the argv is read from the `command` binding then. So `entry = x; running = true; entry = ""` ran with `entry === ""` every time:
```
(probe1)  M16 first argv snapshot  ["got:"]          # entry already cleared when bash ran
          running after two starts: false            # second start while running dropped
$ XDG_CACHE_HOME=<empty tmp> bash -c "echo '' | cliphist delete"
extract id: input not prefixed with id
rc=1
```
Deleting from the launcher never deleted anything; the refresh after exit just re-listed.

Changed: `pending` queue + `busy` flag, argv built at call time with `exec()`, one refresh when the queue drains, non-zero exit logged (commit `fix(cliphist)`).

Check (shimmed `cliphist` logging its stdin):
```
PASS M16 both deletions ran, then a refresh  "delete 1\tfirst entry\ndelete 2\tsecond entry\nlist\n"
```

## L2 — Emojis references properties that do not exist

Verdict: **confirmed**. `root.sloppySearch`, `root.scoreThreshold`, `entries` undefined; the sloppy branch was unreachable, and would have thrown on `entries.slice` if reached.

Changed: the two properties added as in `Cliphist.qml`, `entries` → `root.list` (commit `fix(emojis)`).

Check (real `fuzzel-emoji.sh` copied under the temp `XDG_CONFIG_HOME`):
```
PASS L2 sloppy emoji search works on the loaded list  fuzzy=153 sloppy=73 list=1928
```

## L3 — Privacy binds arrays to bools

Verdict: **confirmed**. `property bool x: [].filter(...)` evaluates to `true` (probe1: `emptyArrBool=true fullArrBool=true`), so both indicators were constant `true`. No consumer in the tree reads them today.

Changed: `.filter(...).map(...)` → `.some(...)` (commit `fix(privacy)`).

Check (probe compares against the same link-group predicate evaluated inline):
```
PASS L3 Privacy.screenSharing matches the link groups  sharing=false
PASS L3 Privacy.micActive matches the link groups  mic=false
```

## L4 — `value == NaN`

Verdict: **confirmed** (`NaN == NaN` → false; caller `AiChat.qml:432` passes `parseFloat(args[0])`).

Changed: `Number.isNaN(value)` (commit `fix(ai)`).

Check: `PASS L4 Number.isNaN catches a bad temperature`.

## L5 — update count overwritten by NaN

Verdict: **confirmed in effect, wrong mechanism**. `wc -l` always prints a number, so a failing `checkupdates` gave `0`, not NaN:
```
$ bash -c 'checkupdates() { echo "error: cannot fetch" >&2; return 1; }; export -f checkupdates; bash -c "checkupdates | wc -l"'
error: cannot fetch
rc=0 out=[0]
```
Either way the last good count was replaced and the button hid.

Changed: run `checkupdates` directly, count lines on exit 0, zero on exit 2, keep the count and warn otherwise (commit `fix(updates)`). Stream-finished ordering was checked first: `ORDER ["stream:hello","exit:3:hello"]`, so the collector is complete inside `onExited`.

Check (shimmed `checkupdates`):
```
PASS L5 failed check keeps the last good count  count=7
PASS L5 a successful check counts the lines  count=3
```
with the shell log line `[Updates] checkupdates failed with code 1 and status 0 - keeping count 7`.

## L7 — `Mpris.players[0]` vs `.values[0]`

Verdict: **confirmed**. `Mpris.players` is an ObjectModel: `Mpris.players[0]=undefined values[0]=… indexOf=function` (probe2).

Changed: `Mpris.players.values[0]` (commit `fix(mpris)`).

Check: `PASS L7 Mpris.players[0] is undefined, .values is the list`.

## L11 (services part) — Audio.qml, PolkitService.qml

Audio: **confirmed**. `0.02 || 0.2` is always `0.02` (dead fallback); `decrementVolume` wrote `volume - step` with no floor.
Changed: fallback dropped, `Math.max(0, …)` on the decrement mirroring the `Math.min(1, …)` on the increment (commit `fix(audio)`).
Check: source pins in the test (`Math.max(0, Audio.sink.audio.volume - step)` present, `0.02 || 0.2` absent); not driven at runtime because it would move the user's volume.

PolkitService: **not a bug**. `!PolkitService.flow?.responseVisible ?? true` parses as `(!x) ?? true`; `!undefined` is already `true`, so every path yields the intended value (flow null → `true`, visible → `false`, hidden → `true`). The `?? true` is unreachable but harmless; left as is, same expression in `PolkitContent.qml:11`, `OverlayContent.qml:14`, `WPolkitContent.qml:14` (not mine).

## L12 (services part) — EasyEffects optimistic toggle

Verdict: **confirmed**. `enable()`/`disable()` set `active` and `execDetached`, never re-read.

Changed: a 1 s one-shot `settleTimer` restarted by both, calling the existing `fetchActiveState()` (commit `fix(easyeffects)`).

Check (shims: `easyeffects`/`flatpak`/`pidof` exit 1, `pkill` exit 0, so the launch "fails"):
```
PASS L12 enable() is optimistic
PASS L12 failed launch reads back as inactive
```

## L13 — LaTeX renderer: exit code ignored, user text spliced into QML source

Verdict: **confirmed**. The expression was interpolated into a JS string literal inside `bash -c` inside `Qt.createQmlObject` source; `"` or a newline broke the component. `renderFinished` fired on any exit code. `escapeBackslashes` existed only to survive the JS-literal layer.
Real MicroTeX behaviour (`/opt/MicroTeX/LaTeX`):
```
good  \frac{1}{2}                      rc=0 size=2889
quote \text{"hi"} \frac{1}{2}         rc=0 size=7766     # renders fine when it reaches argv intact
bad   \frac{1}{                        rc=0 size=1311     # syntax errors render an error box, rc 0
nodir -output=/nonexistent/dir/x.svg   rc=134             # unwritable path aborts
```

Changed: `Process` spawned from a `Component` with the argv passed directly (no shell, no escaping, `workingDirectory` for `res/`), `renderFinished` only on exit 0, hash forgotten otherwise so the next request retries; `qs.modules.common.functions` import dropped, `Quickshell.Io` added (commit `fix(latex)`).

Check (real MicroTeX, temp output dir):
```
PASS L13 quoted multi-line expression rendered to an existing file  [".../out/da279fc58cf4952e0dfd4718d086fc4d.svg"]
PASS L13 failed render is not marked processed  ["da279fc58cf4952e0dfd4718d086fc4d"]
[LatexRenderer] MicroTeX exited with code 6: terminate called after throwing an instance of 'std::ios_base::failure[abi:cxx11]'
```

## Test

`tests/test_services_qml_bugs.sh` (commit `test(services)`), 9 s:
```
ok   source: guarded lines present in MemoryService, Notifications, LauncherSearch, Ai, Audio, MprisController, LatexRenderer
ok   qmllint: 14 touched services parse without errors
PROBE OK
ok   services: cliphist queue, checkupdates exit codes, xkb variants, wallpaper dir validation, easyeffects readback, emoji sloppy search, latex argv and exit code
```

## `./tests/run.sh` tail

```
==> test_workspace_wallpaper_wrap.sh
  ok test_workspace_wallpaper_wrap.sh
58 passed, 0 failed
```
Baseline in `.work/BACKLOG.md` was 56 passed; 58 = baseline + `test_packaged_tools.sh` (J13, already on the branch) + `test_services_qml_bugs.sh`.
