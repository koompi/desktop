# J29 — Migrations delivered and safe: clickable toast, reload guard, per-file refresh, authoring guide (O03 O22 O26 O27)

`.work/OMARCHY-AUDIT.md` rows O03, O22, O26, O27. Omarchy clone at `~/.tmp/omarchy` for the cited lines.
Read first: `dots/.local/bin/koompi-migrate` end to end (247 lines), `dots/.config/systemd/user/koompi-migrate-notify.service`,
`dots/.local/bin/koompi-notify-send` (argv-safe `--exec`), `sdata/install/setups/system.sh` `setup_services` (which user units
`./setup` enables), `sdata/migrations/1787576768-noop-mechanism-check.sh`, `tests/test_migrate_pending_run.sh`, and
`docs/agents/hooks.md` for the doc voice.

## Files you own
- `dots/.local/bin/koompi-migrate` (bash cap 400: `tests/test_file_length.sh`; if it needs more room, new
  `dots/.local/share/koompi/libexec/migrate-lib.sh`, sourced the way `libexec/update` sources `update-lib.sh`)
- `dots/.config/systemd/user/koompi-migrate-notify.service`
- new `docs/agents/migrations.md`; one index line in `docs/agents/SKILL.md` pointing at it
- new `tests/test_migrate_delivery.sh`; `.work/J29-report.md`

## Do
1. (O03) The pending-migration toast is delivered and clickable. Today `ExecStart` runs `notify-send` at
   `graphical-session.target` time, before the shell's notification server exists, so the toast is lost. Wait for a
   notification server (poll `busctl --user list | grep org.freedesktop.Notifications` or `gdbus` NameHasOwner, bounded,
   cite omarchy `bin/omarchy-notification-wait:8-13`), then send through `koompi-notify-send` with `--exec` that opens a
   terminal running `koompi migrate --apply` (find the terminal the tree already prefers: `keybinds.lua` / `variables.lua`
   name it; do not hardcode wezterm without citing that). Keep it login-only and say why in a unit comment
   (omarchy `default/systemd/user/omarchy-migrate-notify.service:2-13`).
2. (O22) `koompi-migrate` pauses Hyprland's config autoreload while it rsyncs `~/.config/hypr/hyprland/`:
   `hyprctl keyword misc:disable_autoreload 1` before, `hyprctl reload` (or restore the keyword) after, in a trap so a
   failed rsync still restores it; no-op with a log line when `HYPRLAND_INSTANCE_SIGNATURE` is unset.
3. (O26) `koompi-migrate refresh <path-under-~/.config>`: replaces one file from the packaged default (the source
   `koompi-migrate` already syncs from), after backing the current one up to the same backup location the tar backup uses
   and printing a unified diff (`diff -u`, exit 1 = differences shown, not an error). Unknown path → error naming where
   defaults live. `koompi migrate` help lists it (the CLI's usage string in `cli/src/main.zig:25` is not yours; report the
   line if it needs updating).
4. (O27) `docs/agents/migrations.md`: when a migration is needed vs a plain default change, the filename rule
   (`<unix-ts>-<slug>.sh`, why the timestamp), idempotency, per-user markers, "never load-bearing", and one worked example.
   `koompi-migrate new <slug>` writes the skeleton with the current timestamp into `sdata/migrations/` when run from a
   checkout (refuse otherwise). Cite `agents/skills/migrations.md` from omarchy for what you kept and dropped.
5. `tests/test_migrate_delivery.sh`: shims `hyprctl`, `busctl`/`gdbus`, `koompi-notify-send`, `rsync` on PATH the way
   `test_migrate_pending_run.sh` does, and proves: autoreload keyword set then restored (also on rsync failure); `refresh`
   backs up, diffs, replaces; `new` writes the skeleton; the unit's ExecStart resolves to a command that exists.

## Acceptance
1. Paste the new test's output and the `./tests/run.sh` tail (baseline 81 passed 3 skipped 0 failed, +1).
2. Paste `koompi-migrate --pending` and `koompi-migrate refresh .config/hypr/hypridle.conf` run against a throwaway
   `HOME` (set `HOME=$(mktemp -d)` with a copied tree), showing the backup path and the diff.
3. `shellcheck -x` on every script you touched: empty. `systemd-analyze --user verify` on the unit: clean.
4. `wc -l` of every owned script under its cap.

## Out of scope
- `libexec/update`, `update-lib.sh`, `koompi-snapshot`, `koompi-reload` (J30 owns update).
- `sdata/dist-arch/**` (a unit already ships via the dots tree; if the PKGBUILD needs a change, report the line).
- Changing what migrations exist or what `--pending`/`run` do.

## Stop conditions
- Never run `koompi-migrate run` or `--apply` against the real `$HOME`; throwaway `HOME` only.
- Do not `systemctl --user restart` anything on this machine; the unit is proven by `systemd-analyze verify` and the test.
- If the toast needs a new IPC surface in the shell, stop and report the file.
