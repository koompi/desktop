# J38 — Factory reset from `@baseline` (O16)

`.work/OMARCHY-AUDIT.md` row O16. `installer/src/post_install.sh:78-95` pins `@baseline` as
"how the OS shipped" with no cleanup algorithm so the pruner never takes it;
`dots/.local/bin/koompi-snapshot` (112 lines) exposes create / list / rollback / `--pre-update`
and nothing else. The handover case — a school laptop passing from one student to the next —
has no command.

## The decision (Rithy, 2026-08-26): option (b), root + home

Reset means: roll the root subvolume back to `@baseline`, **and** remove the human users and
their home directories, so the next person starts at first-boot user creation.
Not (a) (leaves the previous student's files). Not (c) (LUKS re-key is out; KOOMPI OS does not
install encrypted by default — verify that in `installer/src/config.zig` and say so in your report).

## The risk this job exists to get right

Rolling root back and deleting every human user can leave a machine with **no way to log in**.
Before you write the destructive half, establish, with evidence:

- What `@baseline` contains for `/etc/passwd` — does the install create the user before or after
  the baseline snapshot is taken? Read `installer/src/post_install.sh` and `archinstall.zig`.
- Whether `/home` is a separate subvolume (so a root rollback does not touch it) — that is the
  reason the home half needs `userdel -r` at all.
- What re-arms first-boot user creation: `dots/.local/bin/koompi-useradd` is an interactive
  Settings flow behind pkexec, which is **not** a first-boot path. `installer/src/cidata.zig:220`
  has an OEM hostname. If no first-boot path exists, the tool must not offer to delete the last
  administrator — refuse instead, and report the gap as a follow-up job. Do not invent an OEM flow.

## Files you own

- new `dots/.local/bin/koompi-factory-reset`
- `dots/.local/bin/koompi-snapshot` (add a way to resolve the baseline snapshot number; keep every
  existing subcommand's behaviour and its exit-0-when-unavailable contract)
- `sdata/dist-arch/koompi-shell/PKGBUILD` — append the `_tools` row only; **leave `pkgrel` alone**
- new `tests/test_factory_reset.sh`
- `docs/agents/` — a short page only if the tool needs one; do not touch `docs/navigation.md`

## Do

1. Answer the three questions above from the tree, in writing, before any code.
2. `koompi-factory-reset` with the guard order: root (or re-exec via pkexec/sudo the way the
   neighbouring tools do), btrfs root, snapper `root` config, a `baseline` snapshot that exists.
   Any missing → exit non-zero with the reason. Follow `koompi-snapshot`'s "explain and exit"
   style but do **not** exit 0 on refusal here: a factory reset that silently does nothing is worse
   than an error.
3. `--dry-run` prints exactly what would happen — the snapshot number, every user account and home
   directory that would be removed, the reboot step — and changes nothing. Make it the mode that is
   easy to reach and hard to skip past.
4. The real run demands a typed confirmation (the literal word, read from the tty, not `-y`), lists
   the same plan first, then: `userdel -r` each human user (UID ≥ 1000, never system accounts, never
   `root`), then stage the rollback to baseline via snapper, then print the reboot instruction.
   It does **not** reboot.
5. Refuse when the plan would delete every account with `wheel` and no first-boot path was found (2).
6. `tests/test_factory_reset.sh`: shims for `snapper`, `userdel`, `id`, `getent`, `btrfs`, `findmnt`,
   `loginctl` — the real binaries are never reached. Cover: refusal without snapper, refusal without a
   baseline, `--dry-run` listing the right users and changing nothing, the typed-confirmation path
   calling `userdel -r` once per human user and rollback exactly once, the last-admin refusal,
   and that a system UID never appears in any call.
7. `shellcheck` and `shellcheck -x` clean.

## Acceptance

Paste real output for each:

1. The three answers from Do 1, each with `file:line`.
2. `bash tests/test_factory_reset.sh` — every PASS line, rc 0.
3. `koompi-factory-reset --dry-run` **under the test shims**, showing the plan.
4. `koompi-factory-reset --help`, and the refusal messages for: no snapper, no baseline, not root.
5. `shellcheck dots/.local/bin/koompi-factory-reset dots/.local/bin/koompi-snapshot tests/test_factory_reset.sh`
6. `bash tests/test_packaged_tools.sh` — your `_tools` row is listed.
7. `git diff` on `koompi-snapshot` — prove the existing subcommands are untouched.

## Out of scope

- The Search / session-menu entry. The session screen is not where a reset belongs; a Search row
  arrives with O05.
- LUKS, re-provisioning, disk wipe, `@home` subvolume deletion (the users' homes go via `userdel -r`).
- `pkgrel`, and any change to the installer.

## Stop conditions

- **Never run the tool for real, on any machine, in any pane. Only under the shims.**
  No `userdel`, no `snapper rollback`, no `--yes` path outside the test harness.
- No first-boot user-creation path exists in the tree → build the refusal (Do 5), report the gap,
  do not design an OEM flow.
- `@baseline` turns out to contain a user account whose password nobody knows → stop and report;
  that changes what reset means and is Rithy's call.
