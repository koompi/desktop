# J38 — Factory reset from `@baseline` (O16)

Branch `j38-factory-reset`. The tool was never run for real: every invocation below is
under `tests/test_factory_reset.sh`'s shims, and no `userdel`, `snapper rollback`,
`btrfs`, `findmnt` or `loginctl` binary on this machine was reached.

## Acceptance 1 — the three answers, from the tree

### Q1. What `@baseline` contains for `/etc/passwd`: the installed user is already in it.

The install creates the user **before** the baseline snapshot is taken.

`installer/src/archinstall.zig:283-300` is the whole sequence, in order:
`writeUserCredentials` (`installer/src/archinstall.zig:185-201`) emits
`"users": [{ "username": …, "!password": …, "sudo": true }]`; `runArchinstall`
(`installer/src/archinstall.zig:292`) is what actually creates that account; only then does
`runPostInstallHook` (`installer/src/archinstall.zig:300`) run the chroot hook. Inside the
hook, `main()` calls `pin_baseline` second-to-last (`installer/src/post_install.sh:231`), and
`pin_baseline` (`installer/src/post_install.sh:83-94`) snapshots `/`.

`/etc/passwd`, `/etc/shadow` and `/etc/group` all live on `@`, which is what
`snapper -c root` snapshots. So `@baseline` already carries the first user — with `sudo`
(therefore `wheel`) and their password hash. Root is deliberately locked and is not a way
back in (`installer/src/archinstall.zig:187`).

**Consequence, and the reason this matters more than the lockout risk:** a rollback to
`@baseline` *restores* that account and its password. A `userdel -r` run before the rollback
removes the `/etc/passwd` entry only until the reboot. What `userdel -r` removes permanently
is the home directory — see Q2. So a factory reset on a stock install hands the next student
a machine whose only administrator is the **previous** student's account, with the previous
student's password and no home directory.

That is the contract's "`@baseline` turns out to contain a user account whose password
nobody knows" stop condition, in its worse form: the password is known, to exactly the wrong
person. It is reported under "Open decision for Rithy" below rather than silently designed
around, and the shipped tool refuses on a stock install (Do 5) rather than performing it.

### Q2. `/home` is a separate subvolume, so a root rollback does not touch it.

`installer/src/archinstall.zig:108-114` declares the btrfs layout:
`@` → `/`, `@home` → `/home`, `@var_log` → `/var/log`, `@var_cache` → `/var/cache`,
`@snapshots` → `/.snapshots`.

The only snapper config the installer creates is `root`, bound to `/`
(`installer/src/post_install.sh:60`, `snapper -c root create-config /`). `snapper -c root
rollback` therefore swaps the `@` subvolume and leaves `@home` mounted exactly as it was.
Every previous user's files under `/home` survive a rollback untouched — which is precisely
why decision (b) needs `userdel -r` and cannot be done by the rollback alone.

### Q3. No first-boot user-creation path exists on an installed machine.

A first-boot flow does exist in the tree, and it is not reachable after a factory reset:

`sdata/dist-arch/koompi-oem/files/koompi-oem-provision:27-32` is a real
`useradd -m -G wheel` + `passwd` console flow, driven by
`koompi-oem-provision.service` with `ConditionFirstBoot=yes`
(`sdata/dist-arch/koompi-oem/files/koompi-oem-provision.service:3`) and enabled by
`sdata/dist-arch/koompi-oem/files/50-koompi-oem-provision.preset:5`. Three independent
reasons it will not fire after a reset:

1. `koompi-oem` is not a dependency of any edition metapackage — checked
   `sdata/dist-arch/koompi-desktop-hyprland/PKGBUILD`,
   `sdata/dist-arch/koompi-desktop-kde/PKGBUILD` and
   `sdata/dist-arch/koompi-desktop-experience/PKGBUILD`; none of them, and nothing
   transitively, pulls it. It exists only for cidata `defer_provisioning` images
   (`installer/src/config.zig:47-49`, `installer/src/archinstall.zig:160-175`).
2. Even where it is installed, nothing in the install pipeline runs `systemctl preset-all`,
   so the unit is never enabled. The package says so about itself:
   `sdata/dist-arch/koompi-oem/PKGBUILD:6-10` and
   `sdata/dist-arch/koompi-oem/files/50-koompi-oem-provision.preset:2-4`.
3. `ConditionFirstBoot=yes` is evaluated against `/etc/machine-id`. `@baseline` is a snapshot
   of a finished install, so its machine-id is already populated and the unit would be
   skipped even if it were installed and enabled. The script also disables its own unit on
   success (`sdata/dist-arch/koompi-oem/files/koompi-oem-provision:37`).

`dots/.local/bin/koompi-useradd:27-29` is a `pkexec` Settings dialog needing an existing
session, not a first-boot path. `installer/src/cidata.zig:220` is a unit-test fixture's OEM
hostname, not a flow.

So Do 5 applies, and it applies to every stock install: the tool refuses when the plan
removes every `wheel` administrator and no first-boot path is armed. The gap is filed under
"Follow-up jobs" below. No OEM flow was invented.

### Also asked: LUKS

`installer/src/config.zig:44` — `encrypt: bool = false`. The TUI exposes an encryption step
(`installer/src/app.zig:17`, `installer/src/ui.zig:222-224`), but the default is off, so
KOOMPI OS does not install encrypted by default. Option (c), LUKS re-key, would therefore be
a no-op on a default machine even if it were in scope. It is not in scope.
