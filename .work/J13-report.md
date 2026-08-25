# J13 report — packaged tools list + agent docs (O01, O20)

Branch `j13-packaged-tools`, commits `82a0b17d` (PKGBUILD + test) and the docs commit after it.
Files touched: `sdata/dist-arch/koompi-shell/PKGBUILD`, `tests/test_packaged_tools.sh` (new),
`docs/agents/hooks.md`, `docs/agents/plugins.md`, this report. Nothing else.

## Design decision the lead should know about

Do 1 asks for a glob; Acceptance 2 asks for a test that fails on a fake `koompi-zzz`.
A pure glob cannot fail that test: the fake tool would simply ship.
So the PKGBUILD keeps an explicit `_tools` array next to a `_tools_excluded` array, and the test pins
`_tools ∪ _tools_excluded` to `dots/.local/bin/koompi-*` in both directions.
Outcome is the one Do 1 wants (the package cannot drift from the directory without the suite going red),
and a new tool becomes a deliberate decision — ship it or exclude it with a reason on its line — rather than
anything dropped into `bin/` landing in `/usr/bin` on every KOOMPI OS machine.
If the lead prefers the literal glob, the change is a 4-line loop swap; the test's exclusion checks still apply.

## Exclusions (stop condition 1)

Every tool header was read. None is dev-only or repo-relative. Two are excluded for packaging reasons:

- `koompi-session` — installed by the `koompi-session` package (`sdata/dist-arch/koompi-session/PKGBUILD:27`) at the same path; shipping it twice is a pacman file conflict.
- `koompi-update` — `package()` already replaces it with the `koompi-update -> koompi` symlink (`PKGBUILD` line `ln -s koompi ...`); the `sh` shim in `dots/` is the `~/.local/bin` compatibility copy.

`koompi-wallpaper` is a symlink in `dots/` into the hypr tree; `install(1)` follows it, so it is now in `_tools`
and the separate hand-install line is gone. Verified: `usr/bin/koompi-wallpaper` in the package is a regular
8958-byte file (`bsdtar -tvf`).

Dependency added (mentioned per the rules): `python-gobject`, because `koompi-remotedesktop-portal` is a
Python script importing `gi.repository.Gio/GLib` (`dots/.local/bin/koompi-remotedesktop-portal:27-30`) and
nothing in `koompi-shell`'s previous depends pulled it. `pkgrel` bumped 1 → 2 for the new payload.

Observation, not changed (out of scope, not `koompi-*`): `dots/.local/bin/touch-gestures` is run by
`touch-gestures.service` via `%h/.local/bin`, is not packaged by anything, and is not covered by this test.

## Acceptance 1 — `bsdtar -tf <pkg> | grep usr/bin/`

Built with `cd sdata/dist-arch/koompi-shell && makepkg -f --nodeps` (exit 0, `koompi-shell-1.1-2-x86_64.pkg.tar.zst`; the build was rerun after
the PKGBUILD was committed so the listing below is from the committed file).

```
usr/bin/
usr/bin/koompi
usr/bin/koompi-agent-usage-claude
usr/bin/koompi-agent-usage-codex
usr/bin/koompi-agent-usage-pi
usr/bin/koompi-displays
usr/bin/koompi-flatpak-open
usr/bin/koompi-health
usr/bin/koompi-hook
usr/bin/koompi-launch-webapp
usr/bin/koompi-litert-lm-watchdog
usr/bin/koompi-logout
usr/bin/koompi-migrate
usr/bin/koompi-notify-send
usr/bin/koompi-plugin
usr/bin/koompi-quicklook
usr/bin/koompi-reload
usr/bin/koompi-remotedesktop-portal
usr/bin/koompi-settings
usr/bin/koompi-signature
usr/bin/koompi-snapshot
usr/bin/koompi-stacking
usr/bin/koompi-theme
usr/bin/koompi-update
usr/bin/koompi-useradd
usr/bin/koompi-wallpaper
usr/bin/koompi-webapp-install
usr/bin/koompi-webapp-remove
usr/bin/koompi-workbench
```

27 `koompi-*` entries = 26 from `_tools` + the `koompi-update` symlink. `dots/.local/bin` has 28 `koompi-*`
files: 26 shipped + `koompi-session` (its own package) + `koompi-update` (present as the symlink). All accounted for.

`.PKGINFO` depends: `koompi-quickshell-git rsync jq xorg-xprop xorg-xwayland python-gobject`.

## Acceptance 2 — test fails on a fake tool, passes after removal

```
$ bash tests/test_packaged_tools.sh
packaged tools: 26 shipped, 2 excluded, all accounted for
exit=0
$ touch dots/.local/bin/koompi-zzz; chmod +x dots/.local/bin/koompi-zzz; bash tests/test_packaged_tools.sh
FAIL: dots/.local/bin/koompi-zzz is neither in _tools nor in _tools_excluded in koompi-shell/PKGBUILD
exit=1
$ rm dots/.local/bin/koompi-zzz; bash tests/test_packaged_tools.sh
packaged tools: 26 shipped, 2 excluded, all accounted for
exit=0
```

The other direction (a listed name with no file), exercised by renaming `koompi-health` to `koompi-healthx` in `_tools`:

```
FAIL: _tools lists koompi-healthx but dots/.local/bin/koompi-healthx is not an executable file
FAIL: dots/.local/bin/koompi-health is neither in _tools nor in _tools_excluded in koompi-shell/PKGBUILD
exit=1
```

The test also fails if `package()` stops iterating `"${_tools[@]}"`, if a name is in both arrays, or if an
exclusion line has no `# reason` comment.

## Acceptance 3 — suite, shellcheck, namcap

```
$ ./tests/run.sh 2>&1 | tail -4
==> test_workspace_wallpaper_wrap.sh
  ok test_workspace_wallpaper_wrap.sh

57 passed, 0 failed
```

Baseline in `.work/BACKLOG.md` is 56; 57 = baseline plus this test.

```
$ shellcheck tests/test_packaged_tools.sh; echo exit=$?
exit=0
```

(clean; two directives with reasons: SC1090 for the computed `source` path, SC2016 for the literal `"${_tools[@]}"` being grepped.)

`namcap`: not installed on this machine (`command -v namcap` → nothing), so not run.

## Acceptance 4 — first 15 lines of each rewritten doc

`docs/agents/hooks.md`:

```
# Hooks

`koompi-hook <event> [-- NAME=value ...]` (`dots/.local/bin/koompi-hook`) runs every
executable file in `~/.config/koompi/hooks/<event>/` in sorted order. It is also
reachable as `koompi hook ...` (`cli/src/main.zig:26`). KOOMPI's own tools call it
after the thing already happened, so a user or a script can react to a theme change
or an update without editing package files. Don't invent new events casually — there
are two, and each has exactly one call site.

## Events fired today

- `theme-set` — from `dots/.local/bin/koompi-theme:51-69`, after `switchwall.sh`
  returned 0. What changed rides along as environment: `KOOMPI_HOOK_MODE` (`dark` or
  `light`), `KOOMPI_HOOK_SCHEME`, or `KOOMPI_HOOK_COLOR`, one per subcommand;
  `regenerate` sets none of them.
```

`docs/agents/plugins.md`:

```
# Plugins

Two unrelated things share the name "plugin" in this repo. Don't conflate them.

## `plugins/` — Hyprland gesture plugin (real, built)

`plugins/koompi-swipe-progress/` is a C++ Hyprland plugin (`main.cpp`, a `Makefile`,
a `rebuild` script) — native Hyprland plugin API, unrelated to the Quickshell shell
or to any shell-widget concept. If you're asked to add a Hyprland-level gesture or
compositor behavior that can't be expressed in the `hl.*` Lua bridge
(see `docs/agents/hyprland.md`), this is the precedent to follow.

## Shell-widget plugin ("clone-to-fork") — real, PoC scoped to one widget

`PluginSlot.qml` (`dots/.config/quickshell/koompi/modules/common/PluginSlot.qml`) is a
```

Every `file:line` citation in both docs was checked against the source before commit.

## Found, not owned by this job

- `docs/agents/SKILL.md:27-28` still says hooks are "Planned, not yet implemented" and `:31-32` calls the
  shell-widget plugin "not-yet-built". Same O20 defect, one level up; not in this job's file list. Severity: low
  (one-line fixes), but it is the routing page every agent reads first.
- The three user units that run `koompi-remotedesktop-portal`, `koompi-litert-lm-watchdog`, and `touch-gestures`
  use `%h/.local/bin/...` (`dots/.config/systemd/user/*.service`), so they depend on the skel copy, not on
  `/usr/bin`. Packaging the tools does not change that; it only fixes bare-name callers (the CLI, QML, keybinds).

## Not done / caveats

- Package not installed (out of scope; needs sudo).
- `namcap` not run (not installed).
- `koompi hook` / `koompi plugin` on a real KOOMPI OS install remain unverified until the lead installs 1.1-2;
  what is verified is that the package now contains the helpers the CLI execs.
