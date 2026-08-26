# Factory reset

`koompi-factory-reset` hands a machine to its next owner: it rolls the root subvolume back to
the `@baseline` snapshot the installer pinned, and removes every human account and home
directory.
The school-laptop case — one student's machine passing to the next — is what it exists for.

Both halves are needed.
`installer/src/archinstall.zig` puts `/home` on its own `@home` subvolume, and the installer's
only snapper config is `root` on `/` (`installer/src/post_install.sh`), so a rollback never
touches anyone's files; and deleting the accounts alone leaves the previous owner's system
configuration in place.
So the tool runs `userdel -r` for each account with UID ≥ 1000, then stages
`snapper -c root rollback <baseline>`, then prints the reboot step.
It does not reboot, and it never touches root or a system account.

`koompi-snapshot baseline` is the one place that answers "which snapshot is the factory
state".
It reads snapper's `baseline=yes` userdata, which `pin_baseline()` sets and which is also what
keeps the snapshot out of the pruner's reach — an empty cleanup algorithm, deliberately.

## Running it

`koompi-factory-reset` with no arguments is the dry run: it prints the whole plan and changes
nothing.
The real run is `sudo koompi-factory-reset --apply`, which prints the same plan and then reads
the word `RESET` from the terminal.
There is no `-y` and no way to drive it from a script; the confirmation is read from the tty,
not from stdin.

## It refuses rather than half-resetting

Every refusal exits non-zero — a factory reset that quietly did nothing would be worse than an
error.

| Code | Refusal |
| --- | --- |
| 2 | The reset would leave nobody able to get an account: every `wheel` administrator is in the delete list, `@baseline` arms no first-boot user creation, and no other account with a usable password survives. |
| 3 | `@baseline` still carries the previous owner's accounts (see below). |
| 4 | Not root, `/` is not btrfs, no snapper `root` config, or no `@baseline` snapshot. |
| 5 | The confirmation word was not typed. |
| 6 | An account in the plan still has an open login session, which would make `userdel -r` fail halfway. |
| 7 | A step of the real run failed. Accounts are removed before the rollback is staged, so a failed `userdel` stops before anything is staged. |

## Known gap: `@baseline` is not a pristine image

On a normally installed machine the tool refuses with code 3, and that refusal is correct.

`archinstall` creates the first user before `post_install.sh` runs, and `pin_baseline()` is
second-to-last in that hook, so `@baseline` is a snapshot of a *finished* install — its
`/etc/passwd` and `/etc/shadow` already hold the first owner's account and password hash.
Rolling back restores them.
`userdel -r` removes the home directories for good, because `@home` is not rolled back, but the
accounts come back at the next boot.
The next student would inherit the previous student's login.

Nothing in the tree re-arms first-boot user creation either.
`koompi-oem-provision` exists, but `koompi-oem` is not a dependency of any edition metapackage,
nothing in the install pipeline runs `systemctl preset-all` to apply its preset, and its
`ConditionFirstBoot=yes` is evaluated against a `/etc/machine-id` that `@baseline` already has.
`koompi-useradd` needs an existing desktop session, so it is not a way back in.

Closing this needs an installer change — pinning `@baseline` before the user is created, or
pinning a second user-free snapshot — which is out of this tool's scope.
Until then the tool measures both facts on the machine it is run on, prints them in the plan,
and refuses.
