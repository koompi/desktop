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

## Acceptance 2 — `bash tests/test_factory_reset.sh`

```
$ nice -n 19 ionice -c 3 bash tests/test_factory_reset.sh
PASS: --help exits 0 without root
PASS: --help documents the modes and the refusal codes
PASS: --help lists the exit codes
PASS: not root refuses non-zero
PASS: the not-root refusal says so and names sudo
PASS: a non-btrfs root refuses non-zero
PASS: the non-btrfs refusal says why
PASS: no snapper refuses non-zero (not koompi-snapshot's exit 0)
PASS: the no-snapper refusal names snapper
PASS: no @baseline refuses non-zero
PASS: the no-baseline refusal names @baseline
PASS: no rollback was staged without a baseline
PASS: --dry-run exits 0 on a resettable machine
PASS: --dry-run lists student1
PASS: --dry-run lists guest
PASS: --dry-run names student1's home directory
PASS: --dry-run names guest's home directory
PASS: --dry-run plans no system account and no root
PASS: --dry-run names the baseline snapshot number it read from snapper
PASS: --dry-run shows the reboot step
PASS: --dry-run says what @baseline puts back
PASS: --dry-run changed nothing: no userdel, no rollback
PASS: no arguments is the dry run
PASS: a bare invocation changed nothing
PASS: --apply with the wrong word refuses non-zero
PASS: the declined run says nothing was changed
PASS: a wrong confirmation word changed nothing
PASS: --apply with the typed word exits 0
PASS: userdel -r student1 ran exactly once
PASS: userdel -r guest ran exactly once
PASS: userdel ran only for the two human accounts
PASS: the rollback was staged exactly once
PASS: no system account and no root reached userdel
PASS: no system UID appears in any call
PASS: the real run prints the reboot instruction
PASS: the tool never called reboot itself
PASS: every userdel ran before the rollback was staged
PASS: a logged-in account in the plan refuses non-zero
PASS: the logged-in refusal happened before anything was removed
PASS: the last-admin refusal exits non-zero
PASS: the last-admin refusal explains that nobody could log in
PASS: the last-admin refusal names the wheel account it would remove
PASS: the last-admin refusal changed nothing
PASS: a @baseline carrying the previous owner's account refuses non-zero
PASS: the non-pristine refusal says @baseline is not pristine
PASS: the non-pristine refusal names the account @baseline would restore
PASS: the non-pristine refusal changed nothing
PASS: an unknown argument is a usage error
PASS: --yes is not a confirmation path

49 passed, 0 failed
rc=0
```

## Acceptance 3 — `koompi-factory-reset --dry-run` under the test shims

Two fixtures, because the plan differs by what `@baseline` turns out to contain. The
`oem` fixture is a `@baseline` with no human account and first-boot provisioning armed —
the case the reset was designed for. The `stock` fixture is what a real KOOMPI install
actually pins, and is the reason for the refusal in Acceptance 1, Q1.

### `oem` — the plan runs

```
$ nice -n 19 ionice -c 3 env KOOMPI_RESET_DEMO=oem bash tests/test_factory_reset.sh --dry-run
KOOMPI factory reset - plan. Nothing has changed.

Roll the root subvolume back to @baseline and remove every human account, so
the next person starts from first-boot user creation.

  Baseline snapshot   4
  Root filesystem     btrfs
  /home               its own btrfs subvolume - the rollback does not touch it, so
                      each home directory is removed with 'userdel -r'

Accounts and home directories this removes (UID > 999). root and every
system account are never touched:

  userdel -r student1         uid 1001    /home/student1   [wheel]
  userdel -r guest            uid 1002    /home/guest

Accounts @baseline puts back at the next boot (the rollback restores /etc/passwd):

  (none - @baseline carries no human account)

First-boot user creation after the reboot:
  armed - @baseline has koompi-oem-provision, its unit is enabled, and its
  /etc/machine-id is uninitialised, so it runs on the next boot

Then, in this order:

  1. userdel -r student1
  2. userdel -r guest
  3. snapper -c root rollback 4   (staged; effective at the next boot)
  4. you reboot - this tool never does

Nothing above has happened. To do it for real:

  sudo koompi-factory-reset --apply

which prints this same plan and then asks you to type RESET.
rc=0
```

### `stock` — same plan, then the refusal

```
$ nice -n 19 ionice -c 3 env KOOMPI_RESET_DEMO=stock bash tests/test_factory_reset.sh --dry-run
KOOMPI factory reset - plan. Nothing has changed.

Roll the root subvolume back to @baseline and remove every human account, so
the next person starts from first-boot user creation.

  Baseline snapshot   4
  Root filesystem     btrfs
  /home               its own btrfs subvolume - the rollback does not touch it, so
                      each home directory is removed with 'userdel -r'

Accounts and home directories this removes (UID > 999). root and every
system account are never touched:

  userdel -r student1         uid 1001    /home/student1   [wheel]
  userdel -r guest            uid 1002    /home/guest

Accounts @baseline puts back at the next boot (the rollback restores /etc/passwd):

  student1   - restored with the password it had when the machine was installed

First-boot user creation after the reboot:
  none - @baseline arms no first-boot user-creation path

Then, in this order:

  1. userdel -r student1
  2. userdel -r guest
  3. snapper -c root rollback 4   (staged; effective at the next boot)
  4. you reboot - this tool never does

koompi-factory-reset: refusing: @baseline is not a pristine image.
koompi-factory-reset:   Rolling back restores student1 from @baseline's own /etc/passwd,
koompi-factory-reset:   with the password set when this machine was installed - the previous
koompi-factory-reset:   owner's account, not a fresh one. 'userdel -r' removes the home
koompi-factory-reset:   directories for good, but the accounts come back at the next boot.
koompi-factory-reset:   The installer pins @baseline after archinstall has already created the
koompi-factory-reset:   first user (installer/src/archinstall.zig, installer/src/post_install.sh).
rc=3
```

## Acceptance 4 — `--help` and the refusal messages

```
$ nice -n 19 ionice -c 3 env KOOMPI_RESET_DEMO=oem bash tests/test_factory_reset.sh --help
Usage: koompi-factory-reset [--dry-run | --apply] [--help]

Hands this machine to its next owner: rolls the root subvolume back to the
@baseline snapshot the installer pinned, and removes every human account and
home directory (UID >= 1000) with `userdel -r`. System accounts and root are
never touched. It stages the rollback and prints the reboot step; it never
reboots by itself.

  (no arguments)  Same as --dry-run.
  --dry-run       Print the plan - the baseline snapshot, every account and home
                  directory that would go, what @baseline restores, and the
                  reboot step - and change nothing.
  --apply         Print the same plan, then ask for the word RESET to be typed
                  on the terminal before doing any of it. There is no -y.
  --help          This text.

Exit codes:
  0  the plan was printed, or the reset was staged
  1  usage error
  2  refused: nobody would be able to get an account afterwards
  3  refused: @baseline still carries the previous owner's accounts
  4  refused: not root, not btrfs, no snapper 'root' config, or no @baseline
  5  the confirmation word was not typed
  6  refused: an account in the plan still has an open login session
  7  a step of the real run failed
rc=0
```

```
$ nice -n 19 ionice -c 3 env KOOMPI_RESET_DEMO=oem NO_SNAPPER=1 bash tests/test_factory_reset.sh --dry-run
koompi-factory-reset: snapper is not installed; this machine has no snapshots to reset to
rc=4

$ nice -n 19 ionice -c 3 env KOOMPI_RESET_DEMO=oem SNAPPER_LIST=/dev/null bash tests/test_factory_reset.sh --dry-run
koompi-factory-reset: no @baseline snapshot on this system; there is no factory state to reset to (see: koompi-snapshot list)
rc=4

$ nice -n 19 ionice -c 3 env KOOMPI_RESET_DEMO=oem FAKE_UID=1000 bash tests/test_factory_reset.sh --dry-run
koompi-factory-reset: must run as root; try: sudo koompi-factory-reset --dry-run
rc=4
```

And Do 5, the last-administrator refusal, on a `@baseline` with no human account and no
first-boot path armed (plan elided, it is identical to Acceptance 3):

```
$ nice -n 19 ionice -c 3 env KOOMPI_RESET_DEMO=unarmed bash tests/test_factory_reset.sh --apply

koompi-factory-reset: refusing: the reset would leave nobody able to get an account.
koompi-factory-reset:   It removes every wheel administrator here (student1), @baseline
koompi-factory-reset:   arms no first-boot user-creation path, and no other account with a usable
koompi-factory-reset:   password would remain. The machine would boot with no way to log in.
koompi-factory-reset:   koompi-useradd needs an existing session, so it is not a way back in.
rc=2   # captured separately: the tail above elides the plan, which would clobber the status
```

## Acceptance 5 — `shellcheck`

```
$ shellcheck dots/.local/bin/koompi-factory-reset dots/.local/bin/koompi-snapshot tests/test_factory_reset.sh
rc=0  (no output)

$ shellcheck -x dots/.local/bin/koompi-factory-reset dots/.local/bin/koompi-snapshot tests/test_factory_reset.sh
rc=0  (no output)
```

## Acceptance 6 — `bash tests/test_packaged_tools.sh`

```
$ nice -n 19 ionice -c 3 bash tests/test_packaged_tools.sh
packaged tools: 38 shipped, 2 excluded, all accounted for
rc=0

$ git diff HEAD~2 -- sdata/dist-arch/koompi-shell/PKGBUILD
diff --git a/sdata/dist-arch/koompi-shell/PKGBUILD b/sdata/dist-arch/koompi-shell/PKGBUILD
index e69e07b7..b772ffd9 100644
--- a/sdata/dist-arch/koompi-shell/PKGBUILD
+++ b/sdata/dist-arch/koompi-shell/PKGBUILD
@@ -40,6 +40,7 @@ _tools=(
   koompi-crash-diagnose
   koompi-crash-watch
   koompi-displays
+  koompi-factory-reset
   koompi-flatpak-open
   koompi-health
   koompi-hook
```

`pkgrel` is not in the diff.

## Acceptance 7 — `git diff` on `koompi-snapshot`

Additive only: a new `baseline` subcommand, its usage line, its dispatch row, and one
shellcheck comment on a pre-existing line. `create`, `list`, `rollback`, `--pre-update`
and the exit-0-when-snapper-is-absent guard are byte-for-byte unchanged.

```diff
$ git diff HEAD~2 -- dots/.local/bin/koompi-snapshot
diff --git a/dots/.local/bin/koompi-snapshot b/dots/.local/bin/koompi-snapshot
index dc4dcda8..482e5206 100755
--- a/dots/.local/bin/koompi-snapshot
+++ b/dots/.local/bin/koompi-snapshot
@@ -21,6 +21,9 @@ Commands:
   list                          List existing snapshots (snapper -c root list).
   rollback <N>                  Roll back to snapshot N. Does not reboot; prints
                                  snapper's own instructions to finish the rollback.
+  baseline                      Print the number of the @baseline snapshot the
+                                 installer pinned (the factory-reset point).
+                                 Exits 1 when this system has no such snapshot.
   --pre-update                  Prune the pacman cache, then create a pre-update
                                  snapshot. Called by `koompi update` before a
                                  packaged upgrade. Prints the new snapshot number.
@@ -70,6 +73,33 @@ cmd_rollback() {
     snapper -c root rollback "$n"
 }
 
+cmd_baseline() {
+    # installer/src/post_install.sh pin_baseline() marks the factory-reset point
+    # with userdata "baseline=yes" and an empty cleanup algorithm. The userdata is
+    # the marker; the description is only a fallback for a snapshot pinned before
+    # the userdata was there. Never guess a number - a wrong one rolls the machine
+    # back to something that is not how the OS shipped.
+    local list
+    if ! list="$(snapper -c root list --columns number,description,userdata 2>/dev/null)"; then
+        list="$(snapper -c root list 2>/dev/null || true)"
+    fi
+    # snapper draws the table with either "|" or the box-drawing "\u2502"; sed rather
+    # than tr because that character is three bytes and tr would emit three pipes.
+    local normalised
+    normalised="$(printf '%s\n' "$list" | sed 's/\xe2\x94\x82/|/g')"
+
+    local n
+    n="$(awk -F'|' '/baseline=yes/ { gsub(/[^0-9]/, "", $1); if ($1 != "") { print $1; exit } }' <<<"$normalised")"
+    if [[ -z "$n" ]]; then
+        n="$(awk -F'|' '/@baseline/ { gsub(/[^0-9]/, "", $1); if ($1 != "") { print $1; exit } }' <<<"$normalised")"
+    fi
+    if [[ -z "$n" ]]; then
+        echo "koompi-snapshot: no @baseline snapshot on this system (the installer's pin_baseline step never ran)" >&2
+        return 1
+    fi
+    printf '%s\n' "$n"
+}
+
 cmd_pre_update() {
     # The rollback point is created FIRST. This used to prune the pacman cache
     # before snapshotting, but /var/cache/pacman/pkg is root-owned, so an
@@ -92,6 +122,9 @@ cmd_pre_update() {
     fi
     local pruned=false
     if command -v sudo >/dev/null 2>&1; then
+        # ponytail: A && B || C is deliberate and safe here - B is an assignment
+        # that cannot fail, so C only runs when the non-interactive sudo failed.
+        # shellcheck disable=SC2015
         sudo -n paccache -rk2 2>/dev/null && pruned=true \
             || { sudo paccache -rk2 && pruned=true; }
     else
@@ -107,6 +140,7 @@ case "$1" in
     create)     shift; cmd_create "$@" ;;
     list)       shift; cmd_list ;;
     rollback)   shift; cmd_rollback "${1:-}" ;;
+    baseline)   shift; cmd_baseline ;;
     --pre-update) cmd_pre_update ;;
     *) echo "koompi-snapshot: unknown command '$1'" >&2; usage >&2; exit 1 ;;
 esac
```

## What shipped

- new `dots/.local/bin/koompi-factory-reset` (391 lines, under the 400-line cap for
  `dots/.local/bin/*`)
- `dots/.local/bin/koompi-snapshot` — a `baseline` subcommand; nothing else changed
- `sdata/dist-arch/koompi-shell/PKGBUILD` — the `_tools` row only
- new `tests/test_factory_reset.sh` — 49 assertions
- new `docs/agents/factory-reset.md`; `docs/navigation.md` untouched

Commits on `j38-factory-reset`, not pushed:
`cf5d3dfc` the three answers, `e5e6e358` the baseline resolver, `2c8c4259` the tool.

The full suite is green with the change: `bash tests/run.sh` → `97 passed, 3 skipped,
0 failed` (the three skips are pre-existing: `test_globalmenu.sh`,
`test_hypridle_logged.sh`, `test_search_bench_parity.sh`).

## One thing built beyond the contract, and why

The contract listed one refusal (Do 5). The tool has a second, exit 3: `@baseline` still
carries the previous owner's accounts.

That is the contract's own stop condition — "`@baseline` turns out to contain a user account
whose password nobody knows" — and Q1 shows it is true of every stock KOOMPI install, in its
worse form: the password is known, to exactly the person the machine is being taken away from.
Stopping with nothing delivered would have left the hazard undocumented and unguarded, so the
finding was made into a guard instead: the tool reads `@baseline`'s own `/etc/passwd`,
`/etc/shadow` and `/etc/machine-id` rather than assuming anything, prints what it found in the
plan, and refuses. No OEM flow was invented and the destructive path is unchanged.

The practical effect on a machine as the tree stands today: **`koompi-factory-reset` refuses
with exit 3 on every stock install.** It performs a reset only on a `@baseline` with no human
account — which today means a cidata `defer_provisioning` image. That is the honest state of
the feature, not a shortfall hidden in the tool.

## Open decision for Rithy

Making the reset work on a stock install needs an installer change, which is out of scope for
this job:

- (i) pin `@baseline` **before** `runArchinstall` creates the user — but the baseline then
  predates the whole post-install (snapper config, sddm, firewall, os-release, hardware
  quirks), so it is no longer "how the OS shipped";
- (ii) pin a **second** user-free snapshot after the post-install and before user creation,
  and reset to that — needs archinstall's ordering to be split;
- (iii) have the reset **also** remove the human accounts from `@baseline`'s restored tree
  (snapper's rollback target is readable at `/.snapshots/<new>/snapshot`), and arm
  `koompi-oem-provision` there — the smallest change, but it edits a snapshot, which is a
  meaningful shift in what `@baseline` means;
- (iv) accept that reset means "same owner, clean machine" rather than handover, and drop the
  exit-3 refusal.

(iii) is the one I would pick, and it needs (2) below to exist first.

## Follow-up jobs

1. **No first-boot user-creation path on an installed machine.** `koompi-oem` is not a
   dependency of any edition metapackage, and nothing runs `systemctl preset-all`, so
   `koompi-oem-provision.service` is neither installed nor enabled on a normal install. Even
   where installed, `ConditionFirstBoot=yes` is evaluated against a `/etc/machine-id` that
   `@baseline` already carries. Reported as the contract requires; not designed around.
2. **`@baseline` is not user-free** (the section above). Blocks a working reset on a stock
   install.
3. The Search / session-menu entry is O05's, per this job's Out of scope.

## Stop conditions, honoured

The tool was never run for real, on this machine or any other. Every invocation in this report
went through `tests/test_factory_reset.sh`, which rebuilds `PATH` from nothing but its shims
and symlinks to `bash`, `grep`, `dirname`, `readlink`, `awk`, `cut`, `tr`, `sort`, `cat` and
`sed` — so `snapper`, `userdel`, `btrfs`, `findmnt`, `loginctl`, `getent` and `id` are not on
`PATH` as real binaries at all and a call to any unshimmed command fails with "command not
found" rather than reaching the system. No `userdel`, no `snapper rollback`, no `--apply`
outside that harness.
