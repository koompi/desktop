# J49 report — the git route, run rather than read

Branch `j49-git-route`, four commits.
Files touched: `sdata/install/setups/system.sh`, `tests/test_sysdefaults.sh`, new `tests/test_update_from_git.sh`, this report.
Nothing else. `sdata/install/update.sh` and `dots/.local/share/koompi/libexec/update` were read but not edited; everything found in them is under "Findings I did not fix".

Two fixes: the sysctl gap the brief named, and the fwupd gap the lead's addendum named.
Six findings, all with evidence, none in my files.

## The answer to the question that started this

`koompi update` does reach an existing user, and it does deliver.
Run on a machine that is not this one, it pulls the checkout, installs the dependency metas, rebuilds the tools, mirrors the shell tree into `$HOME` and lands the sysdefaults - all 40 tools and all 1066 shell files byte-identical to the checkout, exit 0.
A packaged KOOMPI OS install reaches the same place: the packaged route reports honestly that pacman delivered nothing of ours and hands over to the git route.

Three things stood between that and "the same as our live system", and two are now fixed:
the sysctl drop-in was copied but never applied (fixed), fwupd was never installed (fixed), and an update runs the installer code from *before* its own pull, so any installer-logic change lands one update late (F1, reported - the file is J51's).

## Where the proving was done

| | Arch container (podman, rootless, `--privileged`, systemd pid 1) | Arch VM (qemu/KVM, cloud image, kernel 7.1.8) |
|---|---|---|
| purpose | the brief's container run: `./setup install` then the real `koompi update` | the one thing a container physically cannot do: write a non-namespaced sysctl |
| `/proc/sys` | writable, but a rootless user namespace may only write namespaced keys (`net.*`) | a real kernel; every key writable |
| scope proven | files, tools, units, package state, exit codes, route | the same, plus the live `vm.*` values |

Neither has a Wayland session, a display manager or a logind user manager, so **nothing about the desktop itself was tested** — no Hyprland, no Quickshell on screen, no reload of a running shell.
What is proven below is what a user *ends up with on disk and in systemd*, and what the commands exit with.

This laptop's own state was not touched: `/proc/sys/vm/swappiness` on the host read 60 before the first container started and 60 after the last one, and no `sysctl`, `./setup` or `koompi update` was run outside the two guests.
The container's `origin.git` was advanced by `git fetch` from this worktree, never by a push.

## What I changed

### 1. `setup_low_ram_defaults` never applied the sysctl drop-in — fixed

`sdata/install/setups/system.sh:118-128`, commit `cd255c42`.

The function copied J46's `90-koompi.conf` to `/usr/local/lib/sysctl.d/` and then reloaded what each *other* file needs.
`systemd-sysctl.service` is a boot-time oneshot, and nothing re-ran it, so a git-route user kept the stock values until the next reboot while a packaged user got them at install time from pacman's `25-systemd-sysctl.hook` (`/usr/share/libalpm/scripts/systemd-hook:49-52`).

```bash
if try sudo systemctl restart systemd-sysctl.service; then
    ok "kernel variables applied (swappiness, dirty limits, inotify watches)"
else
    warn "could not apply the kernel variables now; they take effect at the next boot"
fi
```

Restarting the unit, not writing keys, is deliberate and the comment says so: the unit re-reads *every* file in the sysctl.d search path, and that path is the precedence rule — an admin's `/etc/sysctl.d/` file sorts after ours and shadows it by name.
Poking `vm.swappiness` directly would impose a value the machine's own configuration says it should not have.
`try` rather than `run`, like the oomd branch above it: a container or chroot has `/proc/sys` read-only, which is worth saying and not worth aborting an install over.

### 2. The git route never installed fwupd — fixed (lead's addendum, item 1)

`sdata/install/setups/system.sh:243-252`, commit `227e3f50`. I agree with the lead, and the evidence backs it.

`fwupd` is a `koompi-basic` dependency (`sdata/dist-arch/koompi-basic/PKGBUILD:34-35`) and `koompi-sysdefaults`' preset enables `fwupd-refresh.timer` (`files/usr/lib/systemd/system-preset/80-koompi-sysdefaults.preset`), so a packaged user has both.
From git nothing pulled fwupd in, and `setup_services` only warned — which left every from-git machine with no firmware refresh timer *and* no `koompi update --firmware`, since that subcommand shells out to `fwupdmgr`.
Fixed by asking for it by name per distro, exactly as the `ufw` (`:184-190`) and `zram-generator` (`:133-142`) branches already do.

### 3. Tests

`tests/test_sysdefaults.sh:138-143` gained the assertion the brief asked for, alongside the ones for the oomd restart and the user daemon-reload.

`tests/test_update_from_git.sh` is new (commits `064e02f2`, `6e66ed4c`).
It drives the real code rather than reading it: `update_from_git`, `install_files` and `setup_low_ram_defaults` run against a throwaway `HOME` with `sudo` sandboxed into a fake root, and the "checkout" is a directory of symlinks to this tree with no `.gitmodules`, so `install_files`' submodule branch cannot reach the network and nothing is cloned.
It checks the `./setup update` handoff and its argv, every `dots/.local/bin` tool byte for byte, the whole quickshell tree, the three destination classes (mirrored, merged, override slot), the eight sysdefaults drop-ins, and that the sysctl and oomd reloads actually happen.

Four mutations, each caught:

```
--- mutation: drop the sysctl restart
rc=1 FAIL: the sysctl drop-in was copied but never applied; a from-git user waits for a reboot
--- mutation: drop --delete from the shell tree sync
rc=1 FAIL: the shell tree is not mirrored; a file removed upstream would survive in ~/.config/quickshell/koompi
--- mutation: drop the ~/.local/bin sync
rc=1 FAIL: ~/.local/bin/koompi-webapp-install was not delivered
--- mutation: run_update stops calling run_setups
rc=1 FAIL: run_update no longer runs the setups, so the sysdefaults never land on an update
```

---

## Acceptance

### 1. The container transcript's decisive parts

Fresh `archlinux:latest`, systemd as pid 1, a non-root `builder` user, the branch cloned from a bare repo at `/srv/origin.git` (no network clone, and `git pull --ff-only` has a real origin to pull from).

`./setup install -y --no-deps --no-apps`:

```
==> Done
  Log out and pick KOOMPI at your display manager.
  Later on, koompi update (or ./setup update) brings you up to date.

  Super + /       keybind cheatsheet
  App launcher      KOOMPI Workbench (Herdr)
  Ctrl + Super + T pick a wallpaper (this also generates the colour scheme)

  Group changes need a fresh login before ddcutil and ydotool work.
  Run ./setup doctor if something is missing.
SETUP_INSTALL_RC=0
```

`koompi update -y`, the real command, with the full Arch dependency recipe — the route line is the fifth line of the run:

```
  -> lock taken: /tmp/koompi-update-1000.lock (pid 31281)
     $ systemd-inhibit --what=sleep:idle:handle-lid-switch --mode=block --who=koompi-update --why=KOOMPI update in progress tail --pid=31281 -f /dev/null

==> Updating from /home/builder/koompi-desktop
  -> route: from-git (the checkout owns the installed config)
  -> free space on /home/builder/koompi-desktop: 179.6 GiB (needs 2 GiB)
  -> session lock: unlocked (logind LockedHint); ./setup update may restart the shell

==> KOOMPI desktop update
  -> distro: arch 20260802.0.566770 (ID_LIKE: none)
  -> arch:   x86_64
  -> package recipe: sdata/dist-arch
```

The pull is real, not a no-op:

```
Updating 227e3f50..064e02f2
  -> 1 new commit(s)
```

The same two commands on the VM, where the kernel is real:

```
SETUP_INSTALL_RC=0
...
==> Done
  KOOMPI is up to date.
  Your ~/.config/hypr/custom/ overrides were left untouched.
SETUP_UPDATE_RC=0
```

### 2. `sysctl -n vm.swappiness` after the update, without a reboot

**In the VM — 150.** The install was done from the pre-fix tree (`d4d75c47`), so this is the real before/after a user lives through.

Before, immediately after `./setup install` from the pre-fix tree: the file is there and nothing read it.

```
=== VM after ./setup install from the PRE-FIX tree (d4d75c47)
d4d75c47 work: J49/J50/J51 contracts — git-route delivery, koompi-hd rename, release-tag follow
vm.swappiness            = 60
vm.vfs_cache_pressure    = 100
net.ipv4.tcp_mtu_probing = 0
-rw-r--r-- 1 root root 3267 Aug 26 08:39 /usr/local/lib/sysctl.d/90-koompi.conf
systemd-sysctl last ran: Wed 2026-08-26 08:22:35 UTC     (boot was 08:22:30)
```

After the second `./setup update`, on the same boot. It takes two because of F1 below - the first
update pulls the fix but runs the code it sourced before the pull - which is itself part of the
answer to "does the git route deliver":

```
==> Low-RAM defaults (zram, oomd, fast shutdown)
     $ sudo systemctl restart systemd-sysctl.service
  ok kernel variables applied (swappiness, dirty limits, inotify watches)
     $ sudo systemctl daemon-reload
     $ sudo systemctl enable systemd-oomd.service
     $ sudo systemctl restart systemd-oomd.service
  ok systemd-oomd running with the KOOMPI thresholds

=== every key from the drop-in, live, no reboot (boot 2026-08-26 08:22:30, now 2026-08-26 08:42:39)
vm.swappiness                    = 150
vm.vfs_cache_pressure            = 50
vm.page-cluster                  = 0
vm.watermark_boost_factor        = 0
vm.watermark_scale_factor        = 125
vm.dirty_background_bytes        = 67108864
vm.dirty_bytes                   = 268435456
vm.dirty_writeback_centisecs     = 1500
fs.inotify.max_user_watches      = 524288
net.ipv4.tcp_mtu_probing         = 1
```

Boot 08:22:30, `systemd-sysctl` re-ran 08:42:14, reading taken 08:42:39: no reboot, and all ten keys of the drop-in are live.
(`fs.inotify.max_user_watches` happens to equal the kernel default on this image, so it is the one line above that proves nothing on its own.)

**In the container — 60, and that is the container, not our code.**
`vm.*` is not a namespaced sysctl, so a rootless user namespace cannot write it however privileged the container is; the only key of ours the container *can* apply is the netns-scoped one, and it did:

```
=== live values in the container after koompi update
vm.swappiness                = 60
net.ipv4.tcp_mtu_probing     = 1      (0 before the update)
```

`systemd-sysctl` run by hand in the same container, saying exactly where the wall is:

```
Reading config file "/usr/local/lib/sysctl.d/90-koompi.conf"…
Setting '/proc/sys/vm/swappiness' to '150'
Couldn't write '150' to 'vm/swappiness', ignoring: Permission denied
Setting '/proc/sys/net/ipv4/tcp_mtu_probing' to '1'
rc=0
```

Forcing it would mean a rootful privileged container, which writes the *host* kernel — this laptop. That is a stop condition, so the VM answers this item instead.

### 3. The comparison table

Run inside the container after `koompi update -y` finished, comparing the checkout against `$HOME` and `/usr/local/lib`.
Identical numbers on the VM.

```
what                                       expected    found  verdict
------------------------------------------------------------------------------
~/.local/bin tools (identical)                   40       40  OK
  koompi-factory-reset executable                 1        1  OK
~/.config/quickshell/koompi files              1066     1066  OK
  files in $HOME the checkout lacks               0        0  OK
/usr/local/lib sysdefaults drop-ins               8        8  OK
  under /usr/lib (pacman-owned)                   0        0  OK if 0
```

"Identical" is `cmp`, not presence: every one of the 40 tools and 1066 QML/asset files matches the checkout byte for byte.
The two files that differ between checkout and `$HOME` are both meant to: the submodule's `.git` pointer, which `install_files` excludes, and `scripts/global-menu/zig-out/bin/global-menu-daemon`, which is built into `$HOME` and excluded from the sync.

`~/.local/bin` holds 45 entries: the 40 from `dots/.local/bin` plus five the setups build there (`koompi-shelld`, `koompi-global-menu-daemon`, `koompi-agent-memd`, and the AI tooling).

**Did `koompi update` exit 0 and take the route it should?** Both routes, both 0.

*Direct from-git* (no koompi-* package installed, `is_packaged` false):

```
  -> route: from-git (the checkout owns the installed config)
...
==> Done
  KOOMPI is up to date (from-git route). koompi-health reports on the session.
KOOMPI_UPDATE_RC=0
```

*The packaged fallback*, which is the path the brief says every KOOMPI OS user is really on. `koompi-shell` was built from `sdata/dist-arch/koompi-shell` and installed in the container so `is_packaged` would answer true:

```
  -> route: packaged (the desktop ships from pacman packages)
  !! the packaged route delivered nothing of ours: no [koompi] repo is configured and no koompi-* package changed
  -> falling back to the git route: updating from /home/builder/koompi-desktop
...
==> Done
  KOOMPI is up to date (from-git route). koompi-health reports on the session.
KOOMPI_UPDATE_RC=0
```

That fallback (`libexec/update:569-583`) had never been run outside this laptop. It works.

### 4. The two tests

```
$ bash tests/test_sysdefaults.sh
built koompi-sysdefaults-1.0-3-any.pkg.tar.zst
ok test_sysdefaults.sh
rc=0

$ bash tests/test_update_from_git.sh
ok test_update_from_git.sh
rc=0
```

### 5. shellcheck on everything I touched

```
sdata/install/setups/system.sh     shellcheck rc=0   shellcheck -x rc=0
tests/test_sysdefaults.sh          shellcheck rc=0   shellcheck -x rc=0
tests/test_update_from_git.sh      shellcheck rc=0   shellcheck -x rc=0
```

(shellcheck 0.11.0; no output on any of the six invocations.)

### 6. The global menu on an update — yes, it goes stale, and it only bites without cargo

**The line that decides it: `setup:236`.**

```
setup:236:    { $DO_SETUPS || $DO_FILES; } && setup_global_menu
```

`setup_global_menu` is called from `setup` and from nowhere else.
`run_setups` (`sdata/install/setups.sh:27-43`) does not list it — it lists `setup_globalmenu_rs` — and `run_update` (`sdata/install/update.sh:152,154,157`) calls only `run_setups`, `install_files` and `setup_services`.
So an update never rebuilds the Zig daemon.

It is not deleted, either: `install_files` excludes `zig-out` (`files.sh:295`) and rsync's `--delete` does not remove excluded paths, so the binary from the last install survives, unchanged, against QML and Zig sources that just moved.

Measured in the VM, install then two updates:

```
--- '==> Global menu daemon' (the zig step) per run:
install2     1
vmupdate2    0
vmupdate3    0
zig daemon built:      2026-08-26 08:40:30      <- from ./setup install
rust daemon built:     2026-08-26 08:42:14      <- rebuilt by the update
last ./setup update:   2026-08-26 08:42:30
```

Whether the user notices depends on cargo.
`GlobalMenuService.qml:14-20` prefers `~/.local/bin/koompi-global-menu-daemon` and falls back to `../scripts/global-menu/zig-out/bin/global-menu-daemon`, and `setup_globalmenu_rs` *is* in `run_setups`, so on a machine with cargo ≥ 1.87 every update ships a fresh Rust daemon and the stale Zig binary is never loaded.
On a machine where `cargo_usable` fails — the case `globalmenu.sh:42-44` warns about and the QML comment names — the Zig daemon is what runs, and it is frozen at whatever the last `./setup install` built.

A finding, not a fix: `setup` and `sdata/install/update.sh` are not my files.
The one-line shape of it is moving `setup_global_menu` into `run_setups` after the files step, or calling it from `run_update` where `setup:236` calls it from `main`.

### 7. `bash tests/run.sh` tail

```
==> test_workspace_icon_migration.sh
  ok test_workspace_icon_migration.sh
==> test_workspace_wallpaper_wrap.sh
  ok test_workspace_wallpaper_wrap.sh
==> test_zig_build_abort.sh
  ok test_zig_build_abort.sh

100 passed, 3 skipped, 0 failed
skipped: test_globalmenu.sh test_hypridle_logged.sh test_search_bench_parity.sh
run.sh rc=0
```

The three skips are the pre-existing ones (no live `qs`, no bun, no python-evdev), unchanged by this branch.

---

## Lead addendum, item 2 — the koompi-* dependency parity gap

Computed over the `depends[]` closure of `koompi-desktop-hyprland` plus `koompi-session` (what an installer run puts on a KOOMPI OS machine, `installer/src/archinstall.zig:31`), minus everything the git route installs — the fifteen metas of `ARCH_DEP_PKGBUILDS` (`sdata/dist-arch/install-deps.sh:19-35`) and their closure, plus `ufw`, `zram-generator` and now `fwupd` by name — then checked against the container after a full `koompi update -y` had really run the recipe:

```
=== packaged-only dependencies: pacman -T says which are really absent
plymouth
sddm
python-gobject
(printed names are NOT installed; silence means all satisfied)
```

`xorg-xprop`, `xorg-xwayland` and `systemd` came out of the static reading as gaps and are not: the metas pull them in transitively. Three names is the whole gap.

| missing | comes from | what a git-route user loses |
|---|---|---|
| `python-gobject` | `koompi-shell` | `scripts/thumbnails/thumbgen.py:14` and `dots/.local/bin/koompi-remotedesktop-portal:27` both `import gi` — file-manager thumbnails and the remote-desktop portal fail at import |
| `plymouth` | `koompi-branding` | boot splash; `koompi-branding/files/plymouth/` is never installed either |
| `sddm` | `koompi-base`, `koompi-branding` | no display manager is installed, and the KOOMPI SDDM theme and `10-koompi.conf` never land |

The last two are arguably right: a from-git user on their own Arch install already has a display manager and a bootloader, and `sdata/dist-arch/install-deps.sh:4-7` says the desktop-owning packages are left out on purpose.
`python-gobject` is not in that category — it is a runtime import of two shipped tools, and nothing installs it.

Sixteen `koompi-*` PKGBUILDs are never installed by the git route at all (`koompi-apps koompi-base koompi-branding koompi-desktop koompi-desktop-experience koompi-desktop-hyprland koompi-desktop-kde koompi-hyprland-config koompi-kde-config koompi-kiri koompi-oem koompi-plasma koompi-session koompi-shell koompi-swipe-progress koompi-sysdefaults`).
For most that is the design — their *content* is what `./setup` copies into `$HOME` — and `koompi-sysdefaults`' files are installed by `setup_low_ram_defaults` under `/usr/local/lib`. The three names above are the residue that no route covers.

---

## Findings I did not fix

None of these are in my four files. Each was hit by running, not by reading.

### F1 (high) — `./setup update` runs the *previous* version of its own installer code

`setup:19-33` sources `sdata/install/*.sh` at startup. `run_update` then pulls (`sdata/install/update.sh:132`) and only afterwards calls `run_setups` (`:152`) — but bash parsed those functions before the pull, so an update executes the installer logic the user already had.
Anything under `dots/` is unaffected (`install_files` reads the tree when it runs); anything that changes *how* the installer behaves lands one update late.

Two consecutive updates in the VM, same boot:

```
### run 2 — pulls the commit that adds the sysctl restart
Updating d4d75c47..064e02f2
  -> 3 new commit(s)
==> Low-RAM defaults (zram, oomd, fast shutdown)
     $ sudo systemctl daemon-reload                 <- no systemd-sysctl line
     $ sudo systemctl enable systemd-oomd.service
     $ sudo systemctl restart systemd-oomd.service
  vm.swappiness = 60

### run 3 — nothing to pull, the new code is now what got sourced
  ok already up to date at 064e02f2
     $ sudo systemctl restart systemd-sysctl.service
  ok kernel variables applied (swappiness, dirty limits, inotify watches)
  vm.swappiness = 150
```

This matters beyond my fix: every installer-logic change J01-J51 has landed reaches a user one update after they pull it.
The shape of a fix is for `run_update` to re-exec `"$REPO_ROOT/setup" update` once after a successful pull, with a guard variable so it does it only once.
`sdata/install/update.sh` is J51's file and `setup` is nobody's in this round, so I am reporting it rather than reaching across.

### F2 (high) — `arch_install_paru` installs `paru-bin`, which is broken today

`sdata/lib/arch.sh:27` clones `paru-bin`, a prebuilt binary. The recipe upgrades the system first (`install-deps.sh:86`), so the machine ends up on current pacman — `libalpm.so.16` — and the AUR's `paru-bin` 2.1.0-1 is still linked against `libalpm.so.15`.
The first container `koompi update -y` died there:

```
  -> paru not found; building it (needed for the AUR dependencies)
paru: error while loading shared libraries: libalpm.so.15: cannot open shared object file: No such file or directory
  xx command failed: paru -S --needed --noconfirm --asdeps bc cliphist cmake wget ...
  xx aborting (--yes means no interactive recovery)
  xx ./setup update failed
```

This is not a container artefact: any Arch machine without an AUR helper that runs `./setup install` or `koompi update` today gets this, and the update stops before it has done anything.
Building `paru` (the source package, which links against whatever libalpm is installed) instead of `paru-bin` fixed it in the container, and every run below is after that change was made *to the container*, not to the tree.

### F3 (medium) — `setup_local_ai` can take the whole update down, and downloads 2.4 GB unattended

`sdata/install/setups/ai.sh:28-33`. Under `--yes`, `confirm` answers yes, so `run litert-lm import ...` starts a 2.4 GB model download on any machine that does not already have it, and `run` under `ASSUME_YES` calls `die` on failure. A container run aborted the entire install there:

```
OSError: libvulkan.so.1: cannot open shared object file: No such file or directory
  xx command failed: litert-lm import --from-huggingface-repo litert-community/gemma-4-E2B-it-litert-lm ...
  xx aborting (--yes means no interactive recovery)
SETUP_INSTALL_RC=1
```

An optional offline model should not be able to fail an update of the desktop. `try ... || warn` is what the neighbours in that file already use for this class of step.

### F4 (medium) — `setup_toolkit_defaults` guards on the binary, not the schemas

`sdata/install/setups/desktop.sh:67`: `have gsettings` is satisfied by glib2, but the keys it sets live in `gsettings-desktop-schemas`. With one and not the other, `gsettings set` prints `No schemas installed`, exits non-zero, and `run` aborts the install under `-y`. Hit in both guests before that package was installed:

```
     $ gsettings set org.gnome.desktop.interface font-name Google Sans Flex Medium 11 @opsz=11,wght=500
No schemas installed
  xx command failed: gsettings set org.gnome.desktop.interface font-name ...
  xx aborting (--yes means no interactive recovery)
```

On a full `./setup install` the metas bring the schemas in, so this only bites `--no-deps` and partially-provisioned machines — but it turns a cosmetic default into a failed install.

### F5 (low, J12's) — the edition meta does not pull in the shell

`installer/src/archinstall.zig:31` installs `koompi-desktop-hyprland`. Its `depends` are `koompi-base koompi-hyprland koompi-swipe-progress koompi-quickshell-git koompi-widgets koompi-microtex-git koompi-hyprland-config`; `koompi-shell` is depended on only by `koompi-session`, and nothing depends on `koompi-session`.
So the packaged edition installs the Hyprland stack and the config without the shell package. That is the `[koompi]` repo's territory and stays shut per the brief; noting it because it bears directly on "does a KOOMPI OS user get exactly our desktop".

---

## What remains unproven

- **Anything on screen.** No Wayland session, no compositor, no running Quickshell in either guest, so `reload_session` no-ops and the QML that was delivered was never loaded. The delivery is proven; the desktop is not.
- **The user systemd manager.** Neither guest has one (`no user systemd manager here` in every transcript), so `systemctl --user enable` for ydotool, hypridle, touch-gestures and `litert-lm.socket` was skipped rather than exercised, and `app.slice`'s oomd candidacy was never reported by a live manager.
- **`vm.*` sysctls in a container.** Structurally impossible without writing this laptop's kernel; the VM covers it.
- **The `[koompi]` repo half.** By design (J12). The packaged route was exercised only up to its honest "delivered nothing" verdict and the fallback.
- **Two container provisioning steps that are not what a real machine needs**, listed so nothing here is read as cleaner than it was: `gsettings-desktop-schemas` was installed by hand (F4) and `paru` was built from source instead of `paru-bin` (F2). Everything else the guests have, `./setup` and `koompi update` put there.

## Runs, in order

| # | where | command | rc |
|---|---|---|---|
| 1 | container | `./setup install -y --no-deps --no-apps` | 1 — F4, gsettings schemas |
| 2 | container | same, after installing the schemas | 1 — F3, litert-lm/libvulkan |
| 3 | container | same, with `uv` removed | 0 |
| 4 | container | `koompi update -y` | 1 — F2, paru-bin/libalpm |
| 5 | container | `koompi update -y`, paru built from source, full Arch recipe (15 metas, quickshell-git and microtex-git built from the AUR) | 0 |
| 6 | container | `koompi update -y` with `koompi-shell` installed, to reach the packaged fallback | 0 |
| 7 | VM | `./setup install -y --no-deps --no-apps` from the pre-fix tree | 0 (after the same F4 provisioning) |
| 8 | VM | `./setup update -y --no-deps`, pulls the fix | 0 — sysctl not applied (F1) |
| 9 | VM | `./setup update -y --no-deps`, nothing to pull | 0 — swappiness 60 → 150 |

Runs 8 and 9 use `./setup update` rather than `koompi update` because `koompi update` offers no way to skip the dependency recipe and the VM had no reason to rebuild the AUR a second time; `koompi update` reaches `run_update` through exactly that call (`libexec/update:581` in the fallback, `:614` in the direct route), and run 5 exercised the whole of it in the container.
