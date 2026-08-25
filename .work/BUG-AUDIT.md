# Bug audit (opencode, 2026-08-25) — lead notes

Lead verification: **C1 is FALSE** — `/usr/bin/start-hyprland` is owned by stock `hyprland 0.56.2-1`; do not act on it. H1 confirmed (`paccache -rk2` rc=1 unprivileged). Other rows unverified by the lead; each job verifies its own before fixing.

# koompi-desktop bug audit — 2026-08-25

Scope: `setup`, `sdata/lib`, `sdata/install`, `sdata/dist-arch` (PKGBUILDs + scripts),
`cli/` (Zig), `dots/.local/bin`, `dots/.config/hypr`, `dots/.config/quickshell/koompi`
(QML/JS), `tests/`, `.github/workflows`. Vendored trees (`sdata/dist-arch/koompi-quickshell-git/src/`,
build caches) were excluded. Every finding was verified by reading the code; the
few that depend on runtime semantics of Quickshell/Qt versions are marked
"needs verification" with what to check.

Severity counts: 1 critical, 9 high, 21 medium, 24 low.

---

## Critical

### C1. The registered KOOMPI session execs a launcher nothing in this repo provides
**File:** `dots/.local/bin/koompi-session:29-38`; consumers `sdata/install/setups.sh:556-599` (`setup_system_session`), `sdata/dist-arch/koompi-session/PKGBUILD:20`, `dots/.config/zshrc.d/auto-Hypr.sh:6`, `dots/.config/fish/auto-Hypr.fish`

```sh
launcher="${KOOMPI_HYPRLAND_LAUNCHER:-/usr/bin/start-hyprland}"
```

**What is wrong:** `koompi-session` (the `Exec=` of every KOOMPI wayland-session entry, user-level and packaged) hard-execs `/usr/bin/start-hyprland`. No file, PKGBUILD, or script in this repository produces `start-hyprland`; stock Arch `hyprland` does not ship it either. `grep -rn start-hyprland` over the whole repo finds only callers.
**How it fails:** On any machine installed via the documented path — `./setup install` on vanilla Arch, exactly what `install.sh` and `setup` support — `setup_system_session` registers `/usr/share/wayland-sessions/koompi.desktop` system-wide. Picking "KOOMPI" at the display manager runs `koompi-session`, which fails with "not found or not executable" and drops back to the greeter; tty autologin via zsh/fish dies the same way. Login into the desktop is impossible unless the machine already runs KOOMPI OS's out-of-tree hyprland build.
**Fix:** Ship `start-hyprland` (a small wrapper that exports the session env and execs Hyprland with the lua config) from a koompi package or install it in `run_setups`/`files.sh`, or fall back to `Hyprland --config ~/.config/hypr/hyprland.conf` when the wrapper is absent.

---

## High

### H1. Pre-update snapshot is silently skipped and reported as done
**Files:** `dots/.local/share/koompi/libexec/update:171` vs `dots/.local/bin/koompi-snapshot:73-81`
**What is wrong:** `cmd_pre_update()` runs `paccache -rk2` under `set -euo pipefail` *before* creating the snapper snapshot. `/var/cache/pacman/pkg` is root-owned (verified: `drwxr-xr-x root root`), so unprivileged paccache exits 1 (verified live: rc=1) and the script aborts before `snapper create`. The caller ignores the status: `libexec/update` has no `set -e` and its `run()` helper returns without checking.
**How it fails:** Every packaged `koompi update` prints `$ koompi-snapshot --pre-update`, then upgrades the system with **no rollback snapshot**, exactly the scenario the feature exists for.
**Fix:** Run the prune as root (`sudo paccache -rk2`) inside `cmd_pre_update`, or move the prune after the snapshot / tolerate its failure; make `update_packaged` check `run koompi-snapshot --pre-update`.

### H2. `sync_tree` cannot detect rsync failure, but records every path as installed
**File:** `sdata/install/files.sh:226-239`
**What is wrong:** rsync runs inside a process substitution — `done < <(rsync -a "$@" --out-format='%n' ...)`. Its exit status is discarded; the manifest is appended per printed line regardless.
**How it fails:** A failed/partial sync (disk full, permission, dropped tree) still ends with `ok "config files installed"` and a manifest claiming every path was written. Uninstall then deletes files that were never replaced by working copies, leaving the user with a half-old config described as fresh.
**Fix:** Capture rsync's status (`rsync ... > "$tmp"; rc=$?`) and fail `install_files` when non-zero; only add manifest lines after success.

### H3. Packaged shell/skel trees include 371 MB of zig build artifacts
**Files:** `sdata/dist-arch/koompi-shell/PKGBUILD` (`package()`: `cp -a dots/.config/quickshell/koompi …`); `sdata/dist-arch/koompi-hyprland-config/PKGBUILD` (`cp -a "$_repo_root/dots/." "$pkgdir/etc/skel/"`)
**What is wrong:** Both copy the dots tree verbatim. The repo's own `.gitignore` excludes `dots/.config/quickshell/koompi/scripts/global-menu/.zig-cache/` (367 MB here) and `zig-out/`, but they exist in any developer checkout that has built the menu daemon — which `./setup` itself creates routinely. The `./setup` installer excludes these (`sdata/install/files.sh:277-281`); the PKGBUILDs do not.
**How it fails:** Building either package on such a machine ships hundreds of MB of cache into `/etc/xdg/quickshell/koompi` and, worse, into `/etc/skel` — every newly created user gets a private copy in their `$HOME`. Package content is also nondeterministic depending on whether someone built in-tree first.
**Fix:** Exclude `.zig-cache`, `zig-out`, `__pycache__`, `*.pyc`, `.claude`, `.git*` in both PKGBUILD copies (reuse the exclude list from files.sh), e.g. rsync with `--exclude` instead of `cp -a`.

### H4. Pacman-repo build loops never build ttf-koompi-star, a declared dependency meta
**Files:** `sdata/dist-arch/repo/build-repo.sh` (`for pkgdir in "$DIST_ARCH"/koompi-*/`), `.github/workflows/build-packages.yml:61` (same glob)
**What is wrong:** Both iterate `koompi-*/`; the font package directory is `ttf-koompi-star/`. `ttf-koompi-star` is listed in `ARCH_DEP_PKGBUILDS` (`sdata/dist-arch/install-deps.sh:23`) and depended on by `koompi-fonts-themes`.
**How it fails:** The signed `[koompi]` repo (and CI artifacts) are missing a package that installs on KOOMPI OS require; pacman resolution for `koompi-fonts-themes` fails from that repo.
**Fix:** Glob `koompi-*/ ttf-koompi-star/` (or enumerate explicitly).

### H5. build-packages.yml: root-owned PKGDEST makes the job unable to succeed
**File:** `.github/workflows/build-packages.yml:49` vs `:60-66`
**What is wrong:** Step 3 chowns the workspace to `builder`; step 4 then creates `sdata/dist-arch/repo/packages` as root (`install -dm755`) and points `PKGDEST` at it.
**How it fails:** The first `makepkg` as `builder` cannot write its package into the root-owned dir → job fails at the very first package.
**Fix:** `install -dm755 -o builder -g builder …` (or create the dir before the chown).

### H6. AI approval test prints FAIL but can never fail
**File:** `tests/test_ai_approval_scope.sh:62` and `:85-87`
**What is wrong:** Two positive assertions use `console.log(covers(...) ? "PASS…" : "FAIL…")` instead of the file's `eq()`/`grants()` helpers that set `fail = 1`. The script ends `process.exit(fail)`.
**How it fails:** If a risky rule stops covering itself or plain-program keying breaks, the test logs FAIL and exits 0 — the privilege-model positives are unguarded while every negative case around them is tested.
**Fix:** Route both through `grants()`-style checks that increment `fail`.

### H7. Memory daemon always receives an empty embedding API key
**File:** `dots/.config/quickshell/koompi/services/MemoryService.qml:43-47`
**What is wrong:**
```qml
return KeyringStorage.keyringData?.apiKeys?.[id]?.key ?? "";
```
Keys are stored as plain strings under `apiKeys.<id>` (`ModelRegistry.setApiKey` writes `["apiKeys", model.key_id] ← string`; other readers use the string directly). The extra `?.key` turns the string into `undefined`.
**How it fails:** With `ai.memory.provider` set to gemini/openai, `KOOMPI_AGENT_EMBED_KEY=""` is passed on every launch; recall/remember silently degrade to "memory unavailable".
**Fix:** `KeyringStorage.keyringData?.apiKeys?.[id] ?? ""`.

### H8. Overlay pinning/click-through built on a list-to-bool coercion plus non-notifying mutations
**Files:** `dots/.config/quickshell/koompi/modules/koompi/overlay/StyledOverlayWidget.qml:90-92` with `modules/common/Persistent.qml:94`; `overlay/OverlayContext.qml:26-39`; `overlay/OverlayTaskbar.qml:127`
**What is wrong:**
- `property bool open: Persistent.states.overlay.open` binds a bool to `property list<string> open` — an object reference coerces truthy, so `open` never reflects membership; `actuallyPinned`/`actuallyClickable` are constant w.r.t. reality (`close()` at :165 removes from the list but changes nothing here).
- `OverlayContext.pin()/registerClickableWidget()` use `list.push(...)` (the unpin paths correctly reassign), so `hasPinnedWidgets` and the click-through mask bindings get no change notification; same class as `Persistent.states.overlay.open.push(identifier)` in OverlayTaskbar (the sibling branch reassigns).
**How it fails:** Pinned widgets stay visible (or pinning stays inert, depending on Qt's list→bool coercion — needs verification only for *which* symptom); overlay holes/pin-state apply only after an unrelated re-evaluation; JsonAdapter persistence of the pushed value is not triggered.
**Fix:** `readonly property bool open: Persistent.states.overlay.open.includes(root.identifier)`; reassign lists everywhere instead of pushing.

### H9. Failed app recipe still ends with "applications installed"
**Files:** `sdata/install/apps.sh:46` (`source "$recipe"`, status unchecked) and `sdata/dist-arch/install-apps.sh:20` (`arch_install_pkgbuild koompi-apps`, returns 1 unchecked)
**What is wrong:** `deps.sh:23` was fixed to check the sourced recipe's status (its comment says why), but `apps.sh` wasn't. The arch app recipe's `arch_install_pkgbuild` returns 1 on makepkg failure without dying.
**How it fails:** A failed browser/AUR build flows past the mpvpaper prompt into agent installs and `ok "applications installed"` — the exact "aborted then ok" lie deps.sh documents.
**Fix:** `source "$recipe" || { err "…"; return 1; }` in apps.sh, and check `arch_install_pkgbuild koompi-apps || return 1` in the arch recipe.

---

## Medium

### M1. switchwall writes the literal string `"null"` into config.json
**File:** `dots/.config/quickshell/koompi/scripts/colors/switchwall.sh:410` (and `:213`, `:309-334`, same pattern)
**What is wrong:** `imgpath=$(jq -r '.background.wallpaperPath' … || echo "")` — jq exits 0 printing `null` when the key is missing, so `|| echo ""` never fires and `imgpath="null"`.
**How it fails:** `koompi-theme regenerate/--noswitch` before a wallpaper was ever chosen feeds `"null"` to matugen/generate_colors (failures), and `set_wallpaper_path "null"` persists the bogus path into `config.json`.
**Fix:** `jq -er '.background.wallpaperPath // empty'` (or post-validate `-n && != "null"`).

### M2. Theme pipeline sources a venv path that may be unset
**File:** `switchwall.sh:342` (also `:377`)
**What is wrong:** `source "$(eval echo "$ILLOGICAL_IMPULSE_VIRTUAL_ENV")/bin/activate"` — the variable exists only inside a Hyprland session (`hyprland/env.lua`). No default, no error handling; script has no `set -e`.
**How it fails:** Running `koompi-theme` from a plain terminal tries to source `/bin/activate`, continues without the venv, and the material-colors generation then fails (or emits partial SCSS) which `applycolor.sh` consumes anyway.
**Fix:** Default like env.lua does: `VENV="${ILLOGICAL_IMPULSE_VIRTUAL_ENV:-$HOME/.local/state/quickshell/.venv}"`, and abort loudly if activate is missing.

### M3. Gemini wallpaper categorization writes into a directory nothing creates
**File:** `switchwall.sh:199-203`
**What is wrong:** `echo "$img_cat" > "$STATE_DIR/user/generated/wallpaper/category.txt"` — only `$XDG_CACHE_HOME/quickshell/user/generated` is ever mkdir'd (`pre_process`); the state-side `wallpaper/` parent is created nowhere (verified by grep).
**How it fails:** First run with `aiStyling=true` fails the redirect silently (no `set -e`); category is never stored.
**Fix:** `mkdir -p "$(dirname …)"` before the write.

### M4. Test runner counts skipped tests as passes and hides their output
**File:** `tests/run.sh:24-33`; skip guards e.g. `tests/test_touch_gestures.sh:10-12`, `test_ai_correction.sh:19`, `test_session_restore.sh:13`
**What is wrong:** Guarded tests `exit 0` with a "skipping" note on stderr; run.sh increments `passed` on exit 0 and prints captured output only on failure.
**How it fails:** On a fresh machine without bun/node/qs/python-evdev, ~15 tests report green while testing nothing; a regression lands invisible.
**Fix:** Distinct exit code for skips, counted separately; print skip notes always.

### M5. Nothing in CI ever runs the test suite
**Files:** all of `.github/workflows/*` (no invocation of `tests/run.sh` anywhere)
**What is wrong:** AGENTS.md names `./tests/run.sh` as "the checks", but installer.yml only exercises the installer; no workflow runs the suite.
**How it fails:** The 40-test net blocks nothing automatically.
**Fix:** Add a workflow step/job installing bun/jq/python-evdev and running `./tests/run.sh`.

### M6. Timer laps and tray pins never reach disk (in-place list mutation)
**Files:** `dots/.config/quickshell/koompi/services/TimerService.qml:139-141`; `services/TrayService.qml:29-36`
**What is wrong:** `stopwatch.laps.push(...)` and `Config.options.tray.pinnedItems.push(...)` mutate JsonAdapter-backed lists in place. This repo's own convention comment (`services/LaunchpadUsage.qml:35-37`) says reassignment is required for persistence; `unpin()` two lines below reassigns.
**How it fails:** Laps/pins vanish on reload/logout (needs verification only for whether Qt sequence push notifies bindings; disk persistence is not triggered either way).
**Fix:** Reassign: `laps = [...laps, t]`, `pinnedItems = [...pinnedItems, id]`.

### M7. Notification timeout timer crashes on already-dismissed popup
**File:** `dots/.config/quickshell/koompi/services/Notifications.qml:66-73`
**What is wrong:** `const notifObject = root.list[index]; … if (notifObject.isTransient)` with no guard when `index === -1` (popup clicked/discussed before the 7 s timer).
**How it fails:** TypeError in the handler; neither `timeoutNotification` nor `destroy()` runs — one-shot timers leak.
**Fix:** `if (!notifObject) { destroy(); return; }`.

### M8. Launcher runs prefixed sudo commands without a terminal
**File:** `dots/.config/quickshell/koompi/services/LauncherSearch.qml:421-428`
**What is wrong:** The terminal-wrapping branch tests `root.query.startsWith('sudo')`, but the executed string is `cleanedCommand` (prefix stripped). Typing the shell prefix (`"$ sudo …"` style per `search.prefix.shellCommand`) leaves `query` not starting with "sudo".
**How it fails:** Prefixed sudo commands execute via bare `bash -c`, fail with no tty for the password prompt; unprefixed ones work, proving intent.
**Fix:** Test `cleanedCommand.startsWith('sudo')`.

### M9. Calendar week math uses a misspelled property
**File:** `dots/.config/quickshell/koompi/modules/common/widgets/CalendarView.qml:78`
**What is wrong:** `root.locale.firstdayOfWeek` (lowercase d) — undefined; the real property is `firstDayOfWeek` (used correctly in WeekRow.qml). Passing `undefined` selects DateUtils' Monday default.
**How it fails:** Sunday-first locales snap the focused date/month to the wrong weekday; near month edges the focused month label shifts.
**Fix:** `root.locale.firstDayOfWeek`.

### M10. Media duplicate detection treats far-apart players as duplicates
**File:** `dots/.config/quickshell/koompi/modules/koompi/mediaControls/MediaControls.qml:40`
**What is wrong:** `(p1.position - p2.position <= 2 && p1.length - p2.length <= 2)` — no absolute value, and operator precedence applies it even when titles don't match. Any player behind another by more than 2 s satisfies `-diff <= 2`.
**How it fails:** Two distinct players collapse into one control card (wrong one may survive).
**Fix:** `Math.abs(p1.position - p2.position) <= 2 && Math.abs(p1.length - p2.length) <= 2`, nested inside the title-matching group.

### M11. Cover-art download reports success regardless of curl's exit code
**File:** `dots/.config/quickshell/koompi/modules/koompi/mediaControls/PlayerControl.qml:79-87`
**What is wrong:** `onExited: { root.downloaded = true }` ignores `exitCode`; URL interpolated raw into `bash -c` (a `'` in artUrl breaks the command).
**How it fails:** Offline/dead art URL marks downloaded=true; both images show broken forever.
**Fix:** `root.downloaded = (exitCode === 0)`; escape `targetFile`.

### M12. Weather widget throws on every binding evaluation until first successful fetch
**Files:** `modules/koompi/background/widgets/weather/WeatherWidget.qml:36`; `services/Weather.qml:46`
**What is wrong:** `Weather.data?.temp.substring(0, …)` — service initializes `temp: 0` (number); `refineData()` runs only on a successful fetch. `(0).substring` throws; `?? "--°"` cannot catch a throw.
**How it fails:** Console errors and a blank label whenever wttr.in is unreachable; permanently broken offline.
**Fix:** `typeof Weather.data?.temp === "string" ? … : "--°"`.

### M13. Keyboard layout+variant codes are concatenated with no separator
**File:** `dots/.config/quickshell/koompi/services/HyprlandXkb.qml:58-65`
**What is wrong:** `const complexLayout = matchVariant[2] + matchVariant[1];` produces e.g. `usintl`. Consumers compare against hyprctl's plain codes (`InputConfig.qml:90,98`) and display it raw (`HyprlandXkbIndicator.qml:28`).
**How it fails:** With a variant active, the bar shows garbage and Settings never highlights the active layout.
**Fix:** Produce xkb notation `` `${matchVariant[2]}(${matchVariant[1]})` `` and compare accordingly (needs verification of intended format against InputConfig).

### M14. Wallpaper browser applies invalid directories
**File:** `dots/.config/quickshell/koompi/services/Wallpapers.qml:93-104`
**What is wrong:** `root.directory = Qt.resolvedUrl(validateDirProc.nicePath)` executes before the result check; the `"dir"` branch is empty and the `"invalid"` branch is a comment saying "Ignore" — after the change was already applied.
**How it fails:** Browsing to a nonexistent path empties the grid and shows the bad path as current.
**Fix:** Move the assignment into the `result === "dir"` branch.

### M15. Content transparency ignores its master switch
**File:** `dots/.config/quickshell/koompi/modules/common/Appearance.qml:36-37`
**What is wrong:** `backgroundTransparency` gates on `transparency.enable`; `contentTransparency` on the next line does not, though every layer color derives from it.
**How it fails:** Turning transparency off keeps panels semi-transparent.
**Fix:** Wrap line 37 in the same `.enable ? … : 0`.

### M16. Clipboard delete drops rapid second deletions and races its own command string
**File:** `dots/.config/quickshell/koompi/services/Cliphist.qml:83-95`
**What is wrong:** `deleteEntry()` sets `entry`, sets `running = true`, immediately resets `entry = ""` (mutating the binding the argv was built from — safe only if Quickshell snapshots argv synchronously; needs verification); a second delete while running is a silent no-op, yet refresh hides the entry.
**How it fails:** Deleting two entries quickly deletes one; the UI shows both gone.
**Fix:** Queue pending deletions; clear `entry` in `onExited`.

### M17. OSD is pinned to the screen resolved at startup, forever
**File:** `modules/koompi/onScreenDisplay/OnScreenDisplay.qml:16,103-108`; `indicators/BrightnessIndicator.qml:9-10`
**What is wrong:** `focusedScreen` is a one-shot `find(...)`; the `onFocusedScreenChanged` handler that assigns `osdRoot.screen` can never fire because nothing updates the property (tree-wide grep confirms).
**How it fails:** Volume/brightness OSDs always appear on the startup monitor; brightness indicator shows a stale device's value after focus moves.
**Fix:** Bind the PanelWindow's `screen` to a property recomputed from `Hyprland.focusedMonitor` (Connections or re-resolve in `triggerOsd()`).

### M18. Android quick-toggle edit mode mutates the Config list in place
**File:** `modules/koompi/sidebarRight/quickToggles/androidStyle/AndroidQuickToggleButton.qml:195-220`
**What is wrong:** `toggleEnabled/toggleSize/movePositionBy` push/splice/write elements directly on `Config.options.sidebar.quickToggles.android.toggles`; the panel grid binds that list and gets no notification, and JsonObject persistence isn't triggered.
**How it fails:** Edit-mode changes appear only after an unrelated refresh; may not persist.
**Fix:** Clone-modify-reassign.

### M19. Background geometry math poisoned by unchecked magick output
**File:** `modules/koompi/background/Background.qml:225-245`
**What is wrong:** `magick identify` output parsed with no exit-code/validity check; empty output → `Number("") === 0` → `Math.max(w/0, h/0) = Infinity` into `minSuitableScale`.
**How it fails:** Wallpaper scale, parallax offsets and widget-canvas placement go NaN/Infinity when identify fails.
**Fix:** Check `exitCode === 0` and finite numbers before assigning.

### M20. Zig builds use the subshell-abort anti-pattern this repo documents against
**Files:** `sdata/install/setups.sh:30-34` (`setup_koompi_cli`), `:82` (`setup_global_menu`)
**What is wrong:** `( cd "$src" && run zig build … )` — common.sh:103-114 explains why this is wrong (`die` inside a subshell doesn't abort the install) and provides `run_in_dir`. Additionally `setup_global_menu` builds with no `--cache-dir`, so `.zig-cache` grows inside the installed `~/.config/.../global-menu` tree (the same artifacts H3 warns about).
**How it fails:** Under `--yes` a failed zig build exits only the subshell; the install proceeds (caught downstream for the CLI by the missing-binary install, not at all for the global menu beyond a warning-less continue).
**Fix:** Use `run_in_dir`; pass `--cache-dir "$XDG_CACHE_HOME/koompi/build/globalmenu"`.

### M21. `./setup update` reports "already up to date" after a failed pull
**File:** `sdata/install/update.sh:31-42`
**What is wrong:** If `run git pull --ff-only` is answered "skip" at the failure prompt, execution continues and `before == after` prints `ok "already up to date"`.
**How it fails:** A network-failed update announces success.
**Fix:** Track pull success and report accordingly.

### M22. koompi-displays needs lua/luac to persist, declares it nowhere
**File:** `dots/.local/bin/koompi-displays:66-72`
**What is wrong:** Persistence validates the generated monitors.lua with `luac -p` or `lua`; no koompi-* package depends on lua, so a minimal system lacks both.
**How it fails:** Placement hot-applies fine, then every run ends `generated monitors.lua failed lua validation, not persisted` + exit 1 — layout lost at reboot, error message misattributed.
**Fix:** Fall back to writing without validation when no interpreter exists, or add `lua` to koompi-basic/toolkit depends.

---

## Low

### L1. Calendar month-length helpers are wrong across July/August
**File:** `modules/koompi/sidebarRight/calendar/calendar_layout.js:30-43`
`getNextMonthDays(7)` returns 30 (August has 31); `getPrevMonthDays(8)` returns 30 (July has 31). Derive both from `getMonthDays(next/prev)`.

### L2. Emoji search references properties that don't exist on the singleton
**File:** `services/Emojis.qml:22-31` — `root.sloppySearch`/`root.scoreThreshold`/`entries.slice` copied from Cliphist; preference silently never applies; would throw ReferenceError if the flag were true. Use `Config.options?.search.sloppy` and `root.list`.

### L3. Privacy indicators bind arrays to bools
**File:** `services/Privacy.qml:14-15` — `.filter(...).map(...)` missing `.length > 0`; indicator constant. 

### L4. Dead NaN check in temperature validation
**File:** `services/Ai.qml:157` — `value == NaN` is always false; use `Number.isNaN(value)`.

### L5. Update count overwritten by NaN on checkupdates failure
**File:** `services/Updates.qml:63-70` — `checkupdates | wc -l` always exits 0; `parseInt` of garbage → NaN replaces last good count; button hides showing stale "all good".

### L6. Reload-success popup shows the previous failure's text
**File:** `ReloadPopup.qml:19-23` — `onReloadCompleted` clears `failed` but not `errorString`; body Text is `visible: errorString != ""`.

### L7. setActivePlayer fallback indexes the ObjectModel directly
**File:** `services/MprisController.qml:225` — `Mpris.players[0]` (elsewhere `.values[0]`, e.g. :73); null-player path silently no-ops.

### L8. Self-binding and self-comparisons that disable logic
- `modules/koompi/sidebarRight/quickToggles/classicStyle/GameMode.qml:10` — `toggled: toggled` (binding loop warning; default until first click).
- `modules/koompi/overlay/notes/NotesContent.qml:266` — `if (root.content !== root.content)` always false; cursor-restore dead.

### L9. Array-vs-literal comparison blocks translation retry
**File:** `modules/koompi/screenTranslator/ScreenTextOverlay.qml:50` — `visionParagraphs == []` compares references; use `.length === 0`.

### L10. Vertical bar hides by the horizontal bar's height
**File:** `modules/koompi/verticalBar/VerticalBar.qml:128` — right-side auto-hide uses `Appearance.sizes.barHeight` (40 px) while the bar is `verticalBarWidth` (46 px); sliver remains. Left side (:107) is correct.

### L11. Nullish-coalescing precedence bugs (dead fallbacks)
- `modules/koompi/onScreenDisplay/indicators/GammaIndicator.qml:13` — `Hyprsunset.gamma / 100 ?? 0.5` parses `(gamma/100) ?? 0.5`; parenthesize `(gamma ?? 50)/100`.
- `services/Audio.qml:60-70` — `0.02 || 0.2` always 0.02 (same pattern in `ScreenCorners.qml:103`); decrement also lacks a `Math.max(0, …)` clamp.
- `services/PolkitService.qml:20-25` — `!x ?? true` never applies `true`.

### L12. Fire-and-forget processes report success unconditionally
- `modules/koompi/overlay/fpsLimiter/FpsLimiterContent.qml:50-57` — `startDetached()` flips to Success regardless of sed/pkill outcome.
- `modules/common/utils/ImageDownloaderProcess.qml:30-46` (consumer `FloatingImage.qml:84-95`) — no `onExited` handling; failures leave a blank widget silently.
- `services/EasyEffects.qml:26-42` — toggle state optimistic, never re-fetched.

### L13. LaTeX renderer promises images that don't exist and interpolates user text into QML source
**File:** `services/LatexRenderer.qml:54-80` — `renderFinished` emitted regardless of MicroTeX's exit code; `expression` spliced verbatim into `Qt.createQmlObject` input (quotes/newlines break it).

### L14. "Put back" doesn't restore memory until the next recall
**File:** `modules/koompi/intelligence/IntelligenceContext.qml:49-74` — `restoreMemory/restoreAll` only shrink `droppedMemoryIds`; `enforce()` never re-adds, so the pane recounts tokens for memories that won't be sent.

### L15. Unguarded dereferences in overview delegates
- `modules/koompi/overview/OverviewWindow.qml:61` — `windowData.monitor` (only unguarded access in the file).
- `modules/koompi/overview/OverviewWidget.qml:273-279` — release handler reads `windowData.floating/address` unguarded.

### L16. Slide-out Behavior attached to the wrong item
**File:** `modules/koompi/bar/Resource.qml:72-74` — `Behavior on x` sits on the root Item but animates `resourceRowLayout.x`.

### L17. Region selection: unnotified point pushes plus dead helper referencing foreign properties
**Files:** `modules/koompi/regionSelector/RegionSelection.qml:378` (`points.push` on `list<point>`), `CircleSelectionDetails.qml:14-17` (`updatePoints()` reads undeclared `dragging/mouseX/mouseY` and is never called).

### L18. Predictable temp filenames in world-writable /tmp and litter on failure
**File:** `dots/.local/bin/koompi-stacking:73-74,146-147` — `/tmp/.koompi-stacking-mon.$$` symlink-targetable by another local user; left behind if python/hyprctl fails mid-way (no trap). Use `mktemp` + cleanup trap.

### L19. Fixed `.tmp` sibling name races concurrent config writers
**File:** `dots/.local/bin/koompi-wallpaper:148,177,215` — two invocations share `$CONFIG_FILE.tmp`; systemic issue: scripts rewrite `~/.config/koompi/config.json` behind the shell's FileView, which can clobber script changes on its next flush.

### L20. `mktemp -u` race in memory-daemon verification
**File:** `sdata/install/setups.sh:367` — predictable DB filename; use `mktemp` (create) and pass the path.

### L21. Brittle version pins in microtex PKGBUILD
**File:** `sdata/dist-arch/koompi-microtex-git/PKGBUILD:25-28` — `sed 's/tinyxml2.so.10/tinyxml2.so.11/'` and gtksourceviewmm-3.0→4.0 break on the next soname bump; derive from `pkg-config --variable=soname` or drop the sed when upstream fixes it.

### L22. Vacuous backup assertion in installer CI
**File:** `.github/workflows/installer.yml:171` — `test -d "$fake/.koompi-dots-backup" || true` cannot fail; the step's promise ("leaves nothing of ours behind") is untested for backups.

### L23. Same-day ISO rebuild publishes into an existing release tag and dies
**File:** `.github/workflows/build-iso.yml:71-78` with `profiledef.sh` date-only `iso_version`; second dispatch fails at `gh release create` after a full build. Suffix tag with `${GITHUB_SHA::7}`.

### L24. hyprlock battery status reads every power supply, not the battery
**File:** `dots/.config/hypr/hyprlock/status.sh:12,17,22` — `cat /sys/class/power_supply/*/status|capacity | head -1` picks an arbitrary supply; use `$battery/status` etc.

### L25. Hardcoded touchdevice output
**File:** `dots/.config/hypr/hyprland/general.lua:317-319` — `touchdevice.output = "eDP-1"`; on desktop machines with a touchscreen but no eDP panel the mapping targets a nonexistent output.

---

## Checked and sound (notable non-findings)

- `common.sh` sudo keepalive/refresh discipline, `count_shells` cmdline matching, and `reload_session`'s verify-before-reporting loop are correct; the duplicated copy in `dots/.local/share/koompi/libexec/update` matches.
- `sdata/lib/arch.sh` `vercmp` numeric-output check, `-debug` sibling handling, and `--packagelist`-vs-on-disk reconciliation are correct.
- `koompi-remotedesktop-portal` uinput struct packing, keysym shift ordering, and allow-list logic are correct; `busctl` argument order in `koompi-notify-send` is correct.
- `Hyprland.dispatch("hl.dsp.*")` usage is consistent across all 38+ call sites (plugin dispatcher vocabulary, incl. `koompi-logout`'s stock-Hyprland fallback).
- `systemctl list-unit-files bluetooth.service` guard in `setups.sh:204` returns 1 for missing units on current systemd (verified on systemd 261).
- `installer.yml`'s fake-home matrix, artefact-leak find, and override-preservation tail-check assert for real (modulo L22); `run.sh`'s `$?` capture and failure propagation are correct apart from M4.
- All cross-file references claimed above were grep-verified; `koompi-plugin clone`'s ClockWidget/ClockWidgetPopup sources and PluginSlot.qml exist.
