# Migrations

`koompi-migrate` (`dots/.local/bin/koompi-migrate`, sourcing
`dots/.local/share/koompi/libexec/migrate-lib.sh`) does two unrelated jobs.
The plain sync (`koompi-migrate --apply`) copies the KOOMPI-owned code trees from the
packaged defaults into an existing `$HOME`.
Migrations are the other job: one-off scripts under `sdata/migrations/` that repair
per-user state a default change cannot reach.
This page is about the second.
It keeps omarchy's model (`agents/skills/migrations.md:9-32`: per-user markers, idempotent,
run as the user, login-time notifier) and drops what we do not have: `$OMARCHY_PATH`,
the `omarchy-pkg-*` helper family, the 4.0 upgrade special case.

## Migration or default change?

Change the default when the fix lives in a file the sync already owns:
anything under `dots/.config/quickshell/koompi/` or `dots/.config/hypr/hyprland/`, and
`config.json` defaults, which `koompi-migrate` merges three-way (user values win).
Every existing user picks it up at their next `koompi update` or `koompi-migrate --apply`
with no extra code.

Write a migration only when the state is outside those trees or the change is not a
plain overwrite: a file the sync never touches (`~/.config/hypr/custom/`, `hypridle.conf`,
`~/.config/koompi/`), a rename or move, a symlink to relink, a stale user unit to disable,
a value to rewrite in place rather than replace.
If you cannot say which per-user state the script repairs, it is a default change.

## Filename: `<unix-ts>-<slug>.sh`

`koompi-migrate new <slug>` writes the skeleton with the current `date +%s` into
`sdata/migrations/` (`migrate-lib.sh`, `new_migration`).
It refuses outside a checkout: an installed `/usr/bin/koompi-migrate` has no
`sdata/migrations/` three directories up.

The timestamp is there for two reasons.
Glob order runs migrations lexically, and same-width unix timestamps sort chronologically,
so order is the order they were written (`koompi-migrate`, `pending_migrations`).
The filename is also the completion marker: `~/.local/state/koompi/migrations/<filename>`
exists once that user has run it.
Renaming a shipped migration makes it run again for everyone.
Omarchy names the file from the last commit date (`bin/omarchy-dev-add-migration:34`);
we use the current time, which is what the author has in hand before committing.
The slug is lowercase words joined by hyphens, and says what the script fixes.

## Rules for the script body

- Mode `0644`, no shebang: the runner executes it with `bash -euo pipefail`
  (`koompi-migrate`, the `run` branch), so an unset variable or a failed command
  aborts it.
  Keep `# shellcheck shell=bash` on line one so the tree's shellcheck run knows the dialect.
- Idempotent.
  Markers are per user, so a machine-wide repair runs once per user on the machine;
  check the state before touching it and exit 0 when nothing is left to do.
- Per-user only, as the user.
  No `sudo`, no prompts: the login notifier opens a terminal, but `koompi update` runs
  migrations in its own output with nobody watching for a password.
- Never load-bearing.
  A migration must not be the only thing that makes a fresh install work: `/etc/skel` and
  the packaged defaults carry new users, and a migration only catches existing ones up.
  If a new install would break without the migration, the fix belongs in the defaults.
- Never restart the shell or Hyprland.
  `koompi update` reloads after migrations; the login-time run already runs current code.
- A failing migration stops the run and leaves later ones pending; the user sees
  `FAILED <name>`.
  Exit non-zero on a real failure, not on "nothing to do".

## How they reach the user

`koompi-migrate run` applies every pending migration in order and writes the marker
after each success.
`koompi-migrate --pending` lists them (exit 0 if any, 1 if none).
At login, `koompi-migrate-notify.service` (`dots/.config/systemd/user/`) runs
`koompi-migrate notify`: with nothing pending it exits; otherwise it waits for the shell to
own `org.freedesktop.Notifications` and sends a toast through `koompi-notify-send`
whose `--exec` opens the first terminal `variables.lua` prefers, running
`koompi-migrate run --hold`.
Login is the only trigger, and the unit's comment says why.

## Worked example

Say `hypridle.conf` used to be copied from skel with a `lock_cmd` that pointed at a
script we have since renamed.
The sync never touches `hypridle.conf` (it is machine-tuned), so a default change
reaches only new users.

```sh
$ dots/.local/bin/koompi-migrate new hypridle-lock-cmd
/home/me/workspace/koompi-desktop/sdata/migrations/1787652228-hypridle-lock-cmd.sh
```

Body:

```bash
# shellcheck shell=bash
# hypridle.conf seeded before 2026-08 names the old koompi-lock path; point it at
# koompi-session lock. Machine-tuned file, so the sync never rewrites it.
conf="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/hypridle.conf"
[[ -f "$conf" ]] || exit 0
grep -q 'lock_cmd = koompi-lock' "$conf" || exit 0
sed -i 's|lock_cmd = koompi-lock|lock_cmd = koompi-session lock|' "$conf"
echo "hypridle.conf: lock_cmd now koompi-session lock"
```

Second run: the `grep -q` fails, exit 0, nothing rewritten.
A user without the file: exit 0.
Test it against a throwaway home before committing:

```sh
HOME=$(mktemp -d) bash -euo pipefail sdata/migrations/1787652228-hypridle-lock-cmd.sh
```

To rerun one locally, remove its marker and run the migrator again:

```sh
rm ~/.local/state/koompi/migrations/1787652228-hypridle-lock-cmd.sh
koompi-migrate run
```

`tests/test_migrate_pending_run.sh` covers ordering, markers and the stop-on-failure
rule; `tests/test_migrate_delivery.sh` covers `new`, `notify`, `refresh` and the
autoreload guard.
