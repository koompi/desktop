# J29 report: migrations delivered and safe (O03 O22 O26 O27)

Branch `j29-migrations-delivered`. Files touched: `dots/.local/bin/koompi-migrate`,
new `dots/.local/share/koompi/libexec/migrate-lib.sh`,
`dots/.config/systemd/user/koompi-migrate-notify.service`, new `docs/agents/migrations.md`,
one index line in `docs/agents/SKILL.md`, new `tests/test_migrate_delivery.sh`.

## Stop condition hit: the click half of O03 needs a shell change

`koompi-notify-send --exec` encodes the command in the private `koompi-exec-argv` hint.
Nothing in the tree reads that hint.
The notification server is Quickshell's `NotificationServer`
(`dots/.config/quickshell/koompi/services/Notifications.qml:155`), which only invokes
standard actions (`attemptInvokeAction`, `:243-256`); left-clicking a popup does nothing
(`modules/common/widgets/NotificationItem.qml:73-77` handles middle-click dismiss only), and
`shell-services/notifications/src/hints.rs:25-37` decodes eleven keys, none of them ours.
`grep -rn koompi-exec-argv` over the repo returns only `koompi-notify-send` itself.

So the audit's premise ("we already own the argv-safe --exec sender; the units just do not
use it") is half right: the sender exists, the consumer does not.
What this job delivers for O03: the toast now waits for the server and is sent (that half
was lost before), its body says the command to run, and it carries the `--exec` argv so it
becomes clickable the moment the shell honours the hint.
The consumer belongs in `Notifications.qml` (read `notification.hints["koompi-exec-argv"]`
into the `Notif` wrapper) plus a left-click handler in `NotificationItem.qml:73`, invoking it
as `bash -lc 'exec "$@"' -- "${argv[@]}"` per `koompi-notify-send:14-17`.
Not done here: the shell is not in this job's files.

## What changed

- O03 `koompi-migrate notify` (`migrate-lib.sh`, `notify_pending`): exits 0 with nothing
  pending; otherwise polls `busctl --user call org.freedesktop.DBus ... NameHasOwner s
  org.freedesktop.Notifications` every 100 ms, bounded by `KOOMPI_MIGRATE_NOTIFY_WAIT`
  (60 s default; omarchy `bin/omarchy-notification-wait:8-13` polls the same way).
  NameHasOwner rather than a Notify/GetServerInformation call because a method call would
  D-Bus-activate whichever daemon claims the name.
  Then `koompi-notify-send -a KOOMPI -u critical ... --exec <terminal> <self> run --hold`.
  Terminal order is `variables.lua:11`'s (`wezterm foot kitty alacritty konsole kgx uxterm
  xterm`), first one on PATH, each with its own run-a-command spelling as argv elements,
  never a string for `eval` (`launch_first_available.sh` evals its arguments, so it is not
  used).
  No terminal at all: the toast is sent without `--exec`, naming the command.
  The terminal runs `koompi-migrate run --hold`: `run`, then "Press Enter to close" when
  stdin is a TTY, exit status propagated.
  Click runs `koompi-migrate run` (the pending migrations the toast is about), not
  `koompi migrate --apply` as the job text says: `--apply` is the whole-tree sync and would
  leave the migrations pending. Flagging the deviation.
- Unit: `ExecStart=%h/.local/bin/koompi-migrate notify`, `After=graphical-session.target`,
  comment on why login-only (omarchy `default/systemd/user/omarchy-migrate-notify.service:2-13`)
  and why After rather than Before. Still enabled by `sdata/install/setups/system.sh:194`.
- O22 (`migrate-lib.sh`, `pause_autoreload`/`resume_autoreload`): when `--apply` has a dirty
  `~/.config/hypr/*` pair, reads `hyprctl -j getoption misc:disable_autoreload`, sets
  `hyprctl keyword misc:disable_autoreload 1`, installs an EXIT trap that restores the value
  read, rsyncs, then `hyprctl reload` while the watcher is still off (so the reload records the
  new mtimes and re-enabling does not trigger a second one), then restores.
  `HYPRLAND_INSTANCE_SIGNATURE` unset or no `hyprctl`: one `note` line, no calls.
  `hyprctl keyword` itself failing aborts before the rsync rather than syncing under a live
  watcher.
- O26 `koompi-migrate refresh <path>` (`refresh_file`): accepts `.config/x`, `~/.config/x`,
  `$HOME/.config/x`, or `hypr/x` shorthand; refuses `/`, `..` and directories.
  Source is `/etc/xdg/quickshell/koompi/` for shell files, `/etc/skel/<rel>` for the rest
  (`KOOMPI_MIGRATE_XDG`/`KOOMPI_MIGRATE_SKEL` overrides as the sync already has).
  Backup `~/.local/state/koompi/backups/refresh-<ts>-<path with / as _>`, `diff -u` with
  `(yours)`/`(packaged)` labels, exit 1 from diff accepted, then `cp`.
  Identical file: says so, no backup.
  Unknown path: error naming both default locations.
- O27 `koompi-migrate new <slug>` (`new_migration`): `sdata/migrations/$(date +%s)-<slug>.sh`,
  mode 644, `# shellcheck shell=bash` header, refuses unless `../../..` from the script has
  `.git` and `sdata/migrations/` (so `/usr/bin/koompi-migrate new` refuses).
  `docs/agents/migrations.md` written; `docs/agents/SKILL.md` decision tree points at it.
- `koompi-migrate` went to 430 lines, so the non-sync subcommands and the guard moved to
  `migrate-lib.sh`, sourced the way `libexec/update` sources `update-lib.sh` (sibling
  `../share/koompi/libexec/`, `/usr/lib/koompi/`, `$XDG_DATA_HOME/koompi/libexec/`), with a
  loud `die` when missing.

## Not mine, report the line

- `sdata/dist-arch/koompi-shell/PKGBUILD:113-114` installs `update-lib.sh` to
  `/usr/lib/koompi/`; `migrate-lib.sh` needs the same two lines next to it or the packaged
  `koompi-migrate` dies with "migrate-lib.sh not found".
- `cli/src/main.zig:25` usage `koompi migrate [--apply]` should read
  `koompi migrate [--apply|--pending|run|notify|refresh <path>|new <slug>]`.
- `dots/.config/systemd/user/koompi-snapshot-notify.service:12-15` still has the
  `notify-send` TODO the audit mentions; out of my files.

## Acceptance

### 1. New test and `./tests/run.sh` tail

```
$ nice -n 19 ionice -c 3 bash tests/test_migrate_delivery.sh
migrate delivery tests passed
```

```
$ nice -n 19 ionice -c 3 ./tests/run.sh | tail -4
  ok test_zig_build_abort.sh

82 passed, 3 skipped, 0 failed
skipped: test_globalmenu.sh test_hypridle_logged.sh test_search_bench_parity.sh
```

Baseline was 81 passed, 3 skipped, 0 failed; the +1 is `test_migrate_delivery.sh`.

### 2. Throwaway HOME (`HOME=$(mktemp -d)/home`, `dots/.config` copied in, a `# my tweak`
listener appended to `hypridle.conf`, `KOOMPI_MIGRATE_SKEL=$PWD/dots`)

```
$ koompi-migrate --pending
1787576768-noop-mechanism-check.sh
exit=0

$ koompi-migrate refresh .config/hypr/hypridle.conf
  backup written: ~/.local/state/koompi/backups/refresh-20260825-170701-config_hypr_hypridle.conf
--- .config/hypr/hypridle.conf (yours)
+++ .config/hypr/hypridle.conf (packaged)
@@ -27,8 +27,3 @@
     timeout = 900 # 15mins
     on-timeout = $suspend_cmd
 }
-
-# my tweak
-listener {
-    timeout = 60
-}
koompi-migrate: ~/.config/hypr/hypridle.conf replaced with the packaged default
exit=0

$ ls -la ~/.local/state/koompi/backups/
-rw-r--r-- 1 userx userx  951 Aug 25 17:07 refresh-20260825-170701-config_hypr_hypridle.conf
$ cmp ~/.config/hypr/hypridle.conf dots/.config/hypr/hypridle.conf && echo REPLACED_OK
REPLACED_OK
```

`run`/`--apply` were not run against the real `$HOME`; the test's `--apply` runs use its own
`mktemp` HOME with shimmed `hyprctl`/`rsync`.

### 3. shellcheck and unit verify

```
$ (cd dots/.local/bin && shellcheck -x koompi-migrate); shellcheck -x dots/.local/share/koompi/libexec/migrate-lib.sh tests/test_migrate_delivery.sh
(empty)
$ systemd-analyze --user verify dots/.config/systemd/user/koompi-migrate-notify.service
(empty, exit 0)
```

`shellcheck -x` on `koompi-migrate` is run from its own directory, matching the repo's
`# shellcheck source=../…` convention (`tests/test_update_pull_honesty.sh:22`); from the
repo root the `source=` path is reported as not followed (SC1091 info), nothing else.

### 4. Line counts (cap 400)

```
 307 dots/.local/bin/koompi-migrate
 144 dots/.local/share/koompi/libexec/migrate-lib.sh
 144 tests/test_migrate_delivery.sh
```

## Omarchy citations kept and dropped (O27)

Kept from `agents/skills/migrations.md`: per-user markers named by filename (`:22-32`),
idempotency across users, run as the user with no privilege prompts, login-only notifier and
why (`:74-76`), `0644`/no shebang/`bash -euo pipefail` (`:121-125`), test against a
`mktemp` HOME and rerun by deleting the marker (`:150-163`).
Dropped: `$OMARCHY_PATH`, the `omarchy-pkg-*`/`omarchy-cmd-*` helpers, the 4.0 upgrade
carve-out, and the update-lock check in `bin/omarchy-migrate-notify:7-18` (`koompi update`
has no lock file to test; the login-only trigger is the collision guard we have).
Naming: omarchy uses the last commit date (`bin/omarchy-dev-add-migration:34`), ours the
current time plus a slug, as the job asked.
