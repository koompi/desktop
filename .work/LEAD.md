# Lead state — file length refactor + bug campaign

## Goal

Rithy's call, 2026-08-25: the tree has files too long to maintain or upgrade; fix that
by delegation only — the lead plans, agent sessions in their own herdr tabs do the
work, the lead verifies in its own pane. Standard and caps in `.work/AUDIT.md` (ESLint,
kernel, Google shell, Sonar cited). Job table `.work/BACKLOG.md`, contracts
`.work/jobs/J01..J19`. Bug audit (`.work/BUG-AUDIT.md`) and omarchy audit
(`.work/OMARCHY-AUDIT.md`) added J10-J19, which outrank the length campaign.
Gate that ends the campaign: every file in AUDIT.md rows D1-D8 under cap or shrunk,
`tests/test_file_length.sh` green with a trimmed allow-list, `tests/run.sh`, both
`zig build test`, and shellcheck no worse than baseline, all confirmed in the lead's pane.

## Ledger

| id | runner | state | verdict |
|---|---|---|---|
| J01 | claude | verified | 16:05 lead rebased, ran test_file_length (778 under cap, 35 listed), suite 79/3/0, shellcheck clean in lead-verify; test script and conventions section reviewed; ff-merged `d249bf1e`; tab/worktree/branch removed. Report `.work/J01-report.md`. Walk excludes `libexec/update` (695, bash, no extension) and Rust (no cap row); a line "Add libexec/update and the Rust services to the walk" was typed unsent in its pane (Rithy?) — folded into J09's Do as a decision for Rithy: Rust cap (propose 600 like Zig) |
| J02 | claude | verified | 16:15 lead rebased; in lead-verify: zig-pkg gone, only // comments mention vaxis, test_file_length ok, suite 79/3/0; diff = 55 deletions + one .zon comment line; ff-merged `422c58e4`; tab/worktree/branch removed. Report `.work/J02-report.md` |
| J03 | claude | verified | round 1 stopped correctly on a second consumer (`services/Emojis.qml` parsed the script for `### DATA ###`); lead granted Emojis.qml + test_services_qml_bugs.sh for that fix (round 2). Lead rebased; in lead-verify: test_file_length 34 rows, L2 probe 1928 entries, shellcheck clean, suite 79/3/0; ff-merged `7cabe951`, pushed; tab/worktree/branch removed. Report `.work/J03-report.md` |
| J04 | claude | verified | InterfaceConfig.qml 932 → 19 + 11 section files + a `qmldir` (needed: path-loaded files get no generated qmldir); lead: test_file_length 32 rows, worker's headless cage capture shows all 13 sections, suite 78/3/1 with only the known test_ai_e2e load flake (passed standalone in the lead's pane); ff-merged `44da9d72`, pushed; cleaned up |
| J05 | claude | verified | setups.sh 710 → 40 + 9 files; four tests repointed (path only, justified); found+fixed a fresh-machine dry-run abort in setup_agent_memory (own commit); lead: CI shellcheck lines + new files clean, same 22 functions, dry-run rc 0 (172 lines), test_file_length 31 rows, suite 79/3/0; ff-merged `bb8cf96f`; lead added the CI glob `sdata/install/setups/*.sh` to installer.yml as `d1412b39` (shellcheck -x does not lint sourced files, only follows them); pushed |
| J06 | claude | verified | build.zig on 0.16's runner (root_module) as its own commit; main.zig 931 → 112, four new files ≤ 284; lead re-ran on a verified zig 0.14.1 (`~/.cache/lead-zig`): build ok, 5/5 tests, fmt clean, own render capture byte-identical to main's, test_file_length 33 rows, suite 79/3/0; ff-merged `86c616f5`, pushed; tab/worktree/branch removed. Report `.work/J06-report.md`. Sized, not done: the installer's port to zig 0.16 std.Io (110-140 lines across 5 files) — write as J25 |
| J07 | claude | verified | FeedbackService 1094 → 385 + feedbackRules.js 272 + feedbackWrites.js 198 + 4 QtObjects; round 1 stopped on the JS cap, round 2 split the module (lead's option 1); lead: test_ai_correction 29/29, qml layering ok, file-length 35 rows, consumer grep identical to main, suite 79/3/0; ff-merged `4fc3c65b`, pushed; cleaned up |
| J08 | claude | verified | AiChat 1389 → 184 + 6 components + testMessage.js; four extra id couplings expressed as signals; all 22 commands checked live by the worker; lead: qmllint 0 errors on 7 files, file-length 34 rows, suite 80/3/0; ff-merged `1a0b8492`, pushed; cleaned up. Findings: its stray `wtype` keystrokes were the "//////load" that hit the lead pane; `/model` with no argument wipes remote state → J28 |
| J09 | lead | verified | 17:40 scan of tests/file-length-allow.txt on main after J28: every listed file is still over its cap (ModelRegistry.qml 401 vs 400 is the closest), so no row to drop; the split jobs each removed their own row (35 → 34 rows incl. J26's 5 additions). Length campaign closed: AUDIT D1-D8 all landed |
| J10 | claude | verified | root cause was our Rust registrar (blocking pid lookup on its own zbus executor, 2x3 s timeout per Qt window); lead re-ran test_globalmenu, reviewed diff, rebased+ff to main 3fc78fc3, installed daemon to ~/.local/bin (backup .bak-j10), dolphin via exec_cmd 1.37/0.76/0.87 s under load 4 (was 6.3) |
| J11 | opencode | verified | B1 B2 B3 + H1 H2 M21 all confirmed and fixed; 3-way config-defaults merge on all routes with backup + jq validation; lead ran 5 new tests, run.sh 77/2/0, shellcheck 0 vs 4 on main; ff-merged. Config diff (94 leaves) relayed to Rithy for the defaults decision |
| J12 | — | blocked-on-user | |
| J13 | claude | verified | lead re-ran test_packaged_tools (26+2), run.sh 57/57, shellcheck clean; merged ff to main; python-gobject dep added, pkgrel 2 |
| J14 | claude | verified | ~12:30 lead rebased onto main, re-ran test_sysdefaults ok, run.sh 58/58, shellcheck clean, cli zig ok; diff reviewed (helpers `try`/`systemd_running`/`OS_GROUP_ID` all exist); ff-merged main → `b49e613d`; tab, worktree, branch removed. Report `.work/J14-report.md`. Not yet done on this machine: Do 5 live install (sudo, lead) |
| J15 | claude | verified | ~12:55 lead rebased onto main, ran test_keybind_descriptions (149/149), test_keep_awake_lid, shellcheck, luac, qmllint, cli zig in its worktree: all green; the tab+worktree+branch were then removed and main ff-merged to `928f1b01` by someone other than this lead (Rithy, presumably) while the full suite was mid-run; lead re-ran the suite on main in `/tmp/lead-verify-main` (result in Decided). Report `.work/J15-report.md`; live files installed by the worker match main |
| J16 | claude | verified | 9/9 confirmed + koompi-lid addendum; M5 workflow steps were run in a local podman Arch container (3 iterations); lead rebased onto main, run.sh 71 passed 2 skipped 0 failed, shellcheck clean; ff-merged; main green again |
| J17 | claude | verified | 11/11 confirmed; lead ran its 8 new tests + run.sh 66/66 in its worktree, shellcheck only pre-existing info notes; rebased + ff-merged; tab/worktree/branch removed |
| J18 | claude | verified | lead rebased onto main and ran tests/test_services_qml_bugs.sh in its worktree: every PASS line, rc 0; report `.work/J18-report.md`; ff-merged to main `790c539b` by the other lead session (koompi-desktop-0d) while the lead's gates were running |
| J19 | claude | verified | 16 confirmed+fixed, 4 correctly rejected (M17 M18 L16, halves of H8/L17); lead rebased onto main, run.sh 71/2/0, all 21 touched files inside its owned list; ff-merged; pane/worktree/branch removed. Report name was J19-shell-modules-bugs-report.md |
| J20 | claude | verified | not a PAM hole: the unlocks were real verify-match events (a finger on the palm-rest reader); stack hardened anyway (pam_deny terminators, pam/other, LockedHint, start() failure = failed attempt, alsoInhibitIdle cleared). Lead: test_lock_pam ok, run.sh 72/2/0 rebased, live copy == branch; ff-merged 016057e5. Rithy still to confirm one fingerprint unlock works after the change |
| J21 | claude | verified | koompi-launch (systemd-run --scope, 7 ms) routes keybinds, Search, Launchpad, dock; lead ran test_app_slice, run.sh 78/3/0 rebased, luac ok, shellcheck clean, live scope check in app.slice; ff-merged. Not routed (reported): SessionRestore, waffle/**, shell-internal xdg-open; oomctl unverifiable until J14's package is installed (sudo) | contract `f942bb82` (apps into app.slice so oomd can act) |
| J24 | claude | verified | O02 lock/inhibit/2 GiB floor, O10 reboot advice, O21 LockedHint-based lock check in update + koompi-reload; round 2 moved guards into libexec/update-lib.sh (update back to 695); lead: guards test, shellcheck, file-length 34 rows, packaged-tools ok, suite 81/3/0; ff-merged `10e8cec3`. Its finding that koompi-shell installs `update` by name → lead added update-lib.sh to the PKGBUILD (pkgrel 4), built the package and listed both files; pushed |
| J25 | claude | verified | port in 176 lines, one commit per file; lead on zig 0.16: build ok, 5/5 tests, fmt clean, own capture identical to the 0.14.1 main binary, test_file_length ok, suite 79/3/0; ff-merged `7f7ccff6`; lead fixed the two stale 0.14 header comments `c4d3c41b`; pushed; cleaned up. Installer builds on the machine's and CI's zig again |
| J26 | claude | verified | Rust cap 600 + libexec bash; 5 rows added (update 695, mpris 898, network 1198, tray service 682 + watcher 683); lead resolved the allow-list rebase conflict as the union (36 rows), test ok 894/36, shellcheck clean, suite 79/3/0; ff-merged `450b5b50`, pushed; cleaned up |
| J27 | claude | verified | provider table with a stealth/ → tokenra row and an `oxalpha` key slot; default remoteModel stealth/ox-alpha (existing states.json keeps its value); lead: 85 probe assertions, no key material in the tree, 35 rows, suite 80/3/0; ff-merged `377535fe`, pushed; cleaned up |
| J28 | claude | verified | setModel trims and returns early with the current model + usage; probe shows 7 FAILs before, all PASS after; lead: 4/4 probes, file-length 34 rows, suite 80/3/0; ff-merged `c26605eb`, pushed; cleaned up |
| J29 | claude | returned | lead: rebased, diff reviewed (notify waits for the server via NameHasOwner, autoreload guard with EXIT trap, refresh with backup+diff, `new` skeleton); gates running in lead-verify. Stop condition hit correctly: the `--exec` hint has no consumer in the shell → J43. Needs a lead PKGBUILD line for `libexec/migrate-lib.sh` (same gap as J24) |
| J30 | claude | verified | transcript via `script(1)` re-exec (outer appends the exit line, newest 10 kept), `koompi doctor --last-update` with a fixed diagnosis table, `--firmware` and post-upgrade fwupd advice; lead: test ok, suite 82/3/0, shellcheck clean, `update` 687 ≤ 695, diff reviewed (absolute `$0` from the CLI, duplicate `check_restart_needed` removed); ff-merged `6a1e1333`, pushed; cleaned up |
| J31 | claude | verified | IpcHandlers `idle`/`nightlight`/`notifications`, `koompi-toggle` (exit 0/1/2/64), `koompi toggle` in the CLI, four `Super+,` chords in `keybinds_notifications.lua` (keybinds.lua stays 447); lead: job test, packaged tools 29, 149 binds described, luac, shellcheck, qmllint 0 errors, `zig build test`, suite 82 pass + the `test_update_route` red that was main's own (locked seat, see Decided); ff-merged `a76a797b`, pushed; cleaned up |
| J32 | claude | live | |
| J33 | claude | returned | lead: rebased, diff reviewed (ufw profiles in `koompi-sysdefaults` 1.0-2 which now mirrors `/`, chroot writes rules + ENABLED=yes without `ufw enable`, from-git route raw ports + ssh kept, firewalld hand-off; fwupd in koompi-basic 1.0-7; khm OCR data 1.0-4). LocalSend is AUR-only → not added (stop condition; Rithy: koompi-apps already carries two AUR packages, so allow it or not). Gates queued behind J29 |
| J34 | claude | live | |
| J35 | claude | live | |
| J36 | — | after J33 J30 | |
| J37 | — | after J31 | |
| J38 | — | blocked-on-user | factory reset semantics: root only / root+home (recommended) / re-provision+LUKS |
| J39 | — | ready | |
| J40 | — | after J31 J33 | |
| J41 | claude | live | |
| J42 | — | after J33 J31 J30 | |
| J43 | claude | live | |
| J22 | claude | verified | lead reviewed: packaged hypridle.service unit replaces the /dev/null exec, execs.lua + setup_services diff clean, journal shows Got Lock from dbus; J15 finding 3 closed as not-a-bug; round 2 made the live lock test opt-in (KOOMPI_TEST_LIVE_LOCK=1); suite 77/3/0 rebased; ff-merged | contract `453598b3` (hypridle logged / provable Lock) |

## Live now

Lead is `w5:p11`. Returned, gates pending: J29 (lead-verify, suite running), J33 (next). Live, pane ids in `/tmp/lead-<ID>-pane`:
J32 owns `OnScreenDisplay.qml` + `indicators/`, `Battery.qml`, `koompi-hook` events, new `koompi-osd`/`koompi-launch-tui`, `koompi-shell/PKGBUILD`, `cli/src/main.zig`, `launch_sysmon.sh`, `rules.lua`, `docs/agents/hooks.md`.
J34 owns `bar/UpdateBadge.qml` (new), `BarContent.qml`, `Bar.qml`, `bar/*Popup.qml`, `services/Updates.qml`, `keybinds_notifications.lua`→`keybinds_shell_extra.lua`, `hyprland.lua`, `docs/navigation.md`.
J43 owns `services/Notifications.qml`, `widgets/NotificationItem.qml`, (`hints.rs` if used), `koompi-notify-send` comment.
J35 owns `modules/koompi/cheatsheet/**`, `services/HyprlandKeybinds.qml`.
J41 owns new `modules/koompi/screensaver/**`, `KoompiFamily.qml`, `GlobalStates.qml`, `hypridle.conf`.
Watcher: Monitor loop, 45 s, 3-read idle debounce.

## Decided

- Wait for the bug audit before any dispatch (Rithy, explicit). Findings inside a job's
  owned files are folded into that job's Do; findings elsewhere become J10+.
- Runner: opencode for J11; Claude for J13+ (Rithy's later panes); each job gets its own
  herdr tab in `w5` and a git worktree; "max two" waived by Rithy's "delegate a few tabs".
- Caps chosen so only the AUDIT rows fail today; enforcement is a ratchet (J01), so the
  campaign can land in any order and nothing regresses silently.
- `Config.qml`, `fuzzysort.js`, and the five 650-750-line single-concern files are
  allow-listed, not split (AUDIT ALREADY BUILT). `files.sh` (344) is under cap; deferred.
- J06 serial after J02 (same `installer/` tree; J02 deletes, J06 restructures).
- Previous campaign (visual polish, all verified, merged at `137911d6`) archived to
  `.work/archive/2026-08-24-visual-polish/`.
- Stray herdr worktree `~/.herdr/worktrees/koompi-desktop/tokens` (branch `tokens`, no
  commits ahead of main, clean) left alone; not ours.
- 2026-08-25 11:40: Rithy's two bug reports (slow Qt launches; a user's `koompi update` missing features) outrank the length campaign; J10/J11 dispatched immediately.
- J10 root cause measured in the lead's pane, not guessed: xcb 6.3 s vs wayland 0.24 s, four runs each. Dropping xcb globally is Rithy's call (global menu trade).
- J11: worker must not change shipped defaults; it produces the dev-vs-shipped diff and Rithy picks. `[koompi]` repo hosting is J12, blocked-on-user.
- Lead's own `timelaunch.sh` killed Rithy's Telegram by name; the tool in `.work/tools/` now kills only the pid it timed, and every contract says so.
- 2026-08-25 12:30: Rithy pasted the omarchy audit path after asking what is next; read as go-ahead. J13 (bugs O01+O20) dispatched; J14 (O06) and J15 (O07+O11+O04) written and ready; O02/O10/O21 update hardening deferred until J11 verifies (same file). O05 Search command tree is L and needs Rithy's design call first.
- `installer/ zig build test` fails on this machine on main (`build.zig:14` `root_source_file` gone in zig 0.16; `build.zig.zon` says min 0.14). Baseline "4/4" predates the zig upgrade. Not a job regression; gate on cli zig + run.sh + shellcheck until J06 (installer split) fixes build.zig for 0.16 — add that to J06's Do before dispatch.
- Follow-up jobs to write (from J14 report, not yet in BACKLOG): (a) launch apps into `app.slice` scopes (`systemd-run --user --scope --slice=app.slice` or uwsm) so oomd can act — until then O06 is armed, not protecting; (b) `installer/src/post_install.sh` enable `systemd-oomd`; (c) `koompi-base` should pull `koompi-sysdefaults` for the KDE edition; (d) omarchy sysctl row (swappiness 150 etc.), if Rithy wants it.
- 12:47 Rithy: "keep system awake on but still logout". Lead checked: session 3 alive since boot (no logout); keep-awake's systemd-inhibit live and honoured (throwaway hypridle with 3 s timeout never fired, logged 'systemd idle inhibit active'); the lock screens were J15's live lock-session tests. J15 also found the login-time hypridle ignores logind signals (fresh one works) — that would make keep-awake inert at idle; follow-up job once J15's report has the evidence: run hypridle as the packaged user service (`hypridle.service`, graphical-session.target) instead of `hl.exec_cmd`.
- 12:2x: lead rotated into pane `w5:p11` (Rithy: "monitor all those open tabs with job assign, make them work").

- Follow-up jobs from J15's report (koompi-desktop-0d writes the contracts): J20 (critical, security) lock screen unlocks itself ~2.6 s after locking on this machine — journal `PAM _pam_init_handlers: no default config other` + `fprintd.service: Deactivated`, only unlock path `LockScreen.qml:41` on PamContext success, `LockContext.qml` fingerPam with `configDirectory: "pam"`, `pam/fprintd.conf` = `auth sufficient pam_fprintd.so`; owner = lock panel files (`modules/common/panels/lock/**`), not in any live job. J22: hypridle started by `execs.lua:17` with stdout on /dev/null; log it to `$XDG_RUNTIME_DIR/hypridle.log` or run the packaged `hypridle.service` user unit, then prove `Got Lock from dbus` at next login (J15 finding 3, unproven). J15 finding 2 (keep-awake flips on via `LockScreen.qml:113` alsoInhibitIdle on the phantom unlock) folds into J20.

- ~13:05 TWO LEADS: `koompi-desktop-0d` (the original lead, main checkout, 3h old) is still alive and merged J15 (`928f1b01`) and J18 (`790c539b`), wrote+dispatched J20 (`w5:tW`, pane `w5:p15`), and closed the J15/J18 worker panes. Resolved ~13:12: koompi-desktop-0d handed the job tabs to this session (`w5:p11`): this session verifies, merges, closes panes/worktrees, dispatches from BACKLOG and owns LEAD.md; koompi-desktop-0d keeps the PM side (contracts, reporting to Rithy). It writes J21 (oomd app.slice launch path, from J14) and J22 (hypridle logging / user unit, from J15 finding 3) as contracts only; this session dispatches them. The j18 worktree (this pane's cwd) is `git worktree lock`ed so it survives cleanup.
- ~13:05 MAIN IS RED at `928f1b01`..`4459fb21`: `tests/test_packaged_tools.sh` fails because J15 added `dots/.local/bin/koompi-lid` and `koompi-shell/PKGBUILD` `_tools` does not list it. J15's report said 57 passed because its base predates that test; the merge was not re-gated. Fix routed to J16 (owns that PKGBUILD) as an addendum at 13:06: add to `_tools`, bump pkgrel. Until J16 lands, every suite tail is 1 failed.

- `tests/test_ai_e2e.sh` flaked once under load in J18's run.sh and passed twice standalone (koompi-desktop-0d): re-run it standalone before reading a red suite as a regression.
- J16 must remove `/tmp/j16-ci-repo` (7.7G on the 16G tmpfs) at close-out.

- 15:25 CI: the Installer workflow had failed on every push since 2026-08-18 (SC2016 info at the suspend-hook heredoc, setups.sh; then SC2034 SYSTEM_MANIFEST in common.sh). Two directives with reasons, CI's three shellcheck steps clean locally, ff-merged `d552876a`. Not pushed: Rithy has not asked for a push.
- Main at `d552876a` = everything J10-J22 except J12 (blocked-on-user). Rithy's live `~/.config` differs from main in ~60 tracked files (`/tmp/lead-live-drift.txt`); the merged fixes reach the desktop only via `koompi update` / `./setup` (Next action).

- 15:50 CI Tests workflow (J16's) was red on its first run on main: five tests merged after it was written skip in the Arch container and its last step fails on unlisted skips. `a1fe3443`: `lua` added to the install step (test_touch_output only lacked that), the other four listed with reasons (app_slice: no user manager; config_merge, lock_pam: need qs; hypridle_logged: unit + live session). `a2d993ac`: an apostrophe in one reason had closed the single-quoted allow-list string — caught by simulating the step against run.sh's one-line `skipped: a b c` format (expected skips → 0, unlisted → 1). Slip to not repeat: the first push went out before that simulation was right, because the commit ran after `;` not `&&`; verification belongs in the `&&` chain. Both pushed; Tests run at `a2d993ac` pending.

- 16:18 Rithy: job numbers run to J22; anything new is J23+ (defaults pick = J23, update hardening = J24, walk extension for libexec/update + Rust = J25 or J09's Do).
- Tests workflow green at `a2d993ac` (first green run). Lead pushes main after each verified merge so CI checks the merged tree.

- 15:08 Rithy: "load" + "bluetooth seem not able to work": load average 22 on 8 cores from seven workers + lead gates. Lead reniced every build/test process and the worker runtimes to nice 19 / ionice idle; load fell to ~15 within a minute. Bluetooth: adapter powered, service up, nothing blocked; bluetoothd logged adapter power-downs at 14:49 and 15:07 during suite runs, but test_bluetooth.sh is read-only and nothing in the tree powers the radio off — unexplained; asked Rithy for the symptom. Lesson: with more than two workers, run lead gates at nice 19 and never two suites at once.

- 15:20 Rithy: remote AI = 0xAlpha (https://oxalpha.io/ox-alpha-api.html), key given in chat. Lead verified the key against tokenra.io: it authenticates but the account has $0 credit (`insufficient_user_quota`) — nothing will answer until it is topped up. The key is NOT stored anywhere by the lead; Rithy enters it with `/key` in the chat once J27 ships the route. J27 written and dispatched.

- 16:45 J23 (defaults pick) closed with no change: lead regenerated the dev-vs-shipped diff with `update dump-defaults` (53 leaves, `/tmp/lead-defaults-diff.tsv`); every difference is personal (widget positions, city, language, terminal, wallpapers, palette). The two shipped zeros (`ai.memory.compactionThreshold`, `contextWindow`) are documented as "derive from the server". `quickSliders.enable` (B2's original evidence) no longer differs. Rithy can override by naming a leaf.
- J08 compacted once and went idle mid-acceptance with its split committed (f8e979f1); nudged at 16:40 to re-read its contract, finish, restore Rithy's AI state, and report.

- 18:05 Rithy "next." with an empty queue = start the next campaign. Lead picked the remaining OMARCHY-AUDIT S rows (no design call needed) over O05 (needs Rithy) and the ALREADY BUILT splits (Rithy said not to): J29 O03+O22+O26+O27, J30 O28+O31 logic, J31 O24+O12, J33 O25+O17+O31 dep+khm; J32 (O23 O29) and J34 (O09 O34) serial after J31 because of `koompi-shell/PKGBUILD` `_tools` and keybinds. M rows (O08 O13 O14 O15 O16 O18 O19 O30 O32) are wave 3, contracts written when wave 2 lands. Four concurrent: worker runtimes and lead gates at nice 19.
- Rule kept: `keybinds.lua` (447) and `libexec/update` (695) sit on their allow-list rows, so jobs touching them must add code in a sibling file, never grow them.

- 17:40 wave 3 (M rows) contracts J35-J42 written from an Explore agent's cited fact sheet (O14's shell half already exists: `SessionScreen.qml:172-188`; O19 manual left out — prose in Rithy's voice, his call). PKGBUILD `_tools` contention relaxed: workers append rows and leave pkgrel; the lead unions and bumps on merge. Concurrency cap 5 workers.

- J29 found the `--exec` hint has no consumer in the shell (toasts are never clickable). J43 written; J37/J40 toasts inherit that gap until it lands.

- 18:50 MAIN WAS RED after J30 (`6a1e1333`): `tests/test_update_route.sh` failed on main itself. Cause: J24's `session_locked` asks the real logind for `LockedHint`, and Rithy's seat was locked; the test never shimmed `loginctl`. J30's gate suite passed an hour earlier only because the seat was unlocked then. Lead fix `6b02ca5a` (loginctl shim in that test; `test_config_merge` checked, unaffected). Lesson: a test that reaches the live session is red on a schedule nobody controls; every update test must shim `loginctl`, `qs`, `hyprctl`.
- Two API "Connection lost" drops (J33's pane, the first Explore agent) around 17:05; both resumed with one line. Not load: load was 1.1.
- PKGBUILD contention rule for wave 3 applied; pkgrel is bumped by the lead at merge. J31 bumped to 5 itself (pre-rule); J32 continues from there.

## Next action

Read `/tmp/lead-j29-gates.log` (J29) → ff-merge + lead PKGBUILD line for `migrate-lib.sh` (pkgrel 6) → J33 gates (its test, sysdefaults test, CI shellcheck lines, makepkg the three packages, suite) → ff-merge, push. Then J39 dispatch (ready; 5 live is the cap). After J33 verified: J36, J42 ready (J42 also needs J31 ✓ J30 ✓). After J43 verified: nothing else blocked on it (J37/J40 are `after J31`, already met — dispatch them as slots free). J38 waits on Rithy (factory-reset semantics); LocalSend AUR question waits on Rithy. Still waiting on Rithy from wave 1: J12, sudo installs, `koompi update` here, 0xAlpha credit + `/key`, Bluetooth symptom, fingerprint check.
