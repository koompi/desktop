# J52 — Second rename: koompi/koompi-hd → koompi/koompi-desktop

Rithy, 2026-08-26, after J50 landed: `koompi-hd` names one flavour, and the repo is about to carry
two (HD on Hyprland, SD on Otto — `docs/design/koompi-sd.md`). The flavour belongs in the branch
(`prod-hd`, `prod-sd`), not in the repo. So the repo is `koompi/koompi-desktop`.

Both renames are already done on GitHub and `origin` is re-pointed:
`koompi/desktop` → `koompi/koompi-hd` → `koompi/koompi-desktop`, and the dormant 2021 repo that held
the name was renamed to `koompi/koompi-desktop-2021` (nothing deleted, its redirect intact).
GitHub redirects every old URL, so nothing is broken while you work.

**This is J50 in reverse, with a map you already have.** Read `.work/J50-report.md` first: its
classification table names every occurrence and which bucket it is in. The same rule holds and is
still the thing to get right — `koompi-desktop-hyprland`, `-kde`, `-experience` and the transitional
`koompi-desktop` alias are real `pkgname=` values, and `installer/src/archinstall.zig:31-32` pacstraps
those literals. The repo now shares a string with a package name again, exactly as before today, so
classify by context and never by pattern.

## Files you own

Every file J50 touched, and only for the identity/URL occurrences:

- `install.sh` (`REPO_URL`, `DEST`), `dots/.local/share/koompi/libexec/update` (`UPSTREAM_REPO`,
  `CLONE_DIR`, the `resolve_checkout` guess list, the user-facing texts)
- `README.md`, `docs/agents/SKILL.md`, `docs/agents/migrations.md`
- `modules/settings/About.qml`, `welcome.qml`, `services/SearchBench.qml`
- `cli/src/main.zig`, `sdata/dist-arch/iso/koompi/airootfs/etc/os-release`,
  `installer/src/post_install.sh`
- the five PKGBUILD `url=` fields, `koompi-branding/PKGBUILD` release-asset comments, the five
  `$srcdir` BUILD NOTEs, `sdata/dist-arch/repo/README.md`
- `tests/test_iso_release_tag.sh`, `tests/test_resolve_checkout_paths.sh`
- `sdata/install/update.sh` — **only** `origin_is_koompi()`, if it needs it

## Do

1. Every `koompi/koompi-hd` URL becomes `koompi/koompi-desktop`.
2. `CLONE_DIR` and `install.sh`'s `DEST` become `koompi-desktop` — Rithy's call, and it is also what
   users who installed before today already have on disk.
3. `resolve_checkout`'s guess list must now find **all three** generations: `koompi-desktop`,
   `koompi-hd`, `koompi-hyprland` (and `koompi-os`). Anyone who ran `koompi update` in the last hour
   has a `koompi-hd` directory; they must be found, not cloned over. Put the current name first and
   keep the comment truthful about why each is there.
4. `origin_is_koompi()` (`sdata/install/update.sh`) already matches `koompi/koompi-(hd|desktop)`.
   Confirm it still accepts every generation a real machine can have, including the pre-rename
   `koompi/desktop`, and fix it if it does not — a false negative there means `koompi update` quietly
   stops following `prod-hd`.
5. `tests/test_resolve_checkout_paths.sh` is your check: extend it so a `koompi-hd` checkout is found
   too, not just a `koompi-desktop` one.
6. `shellcheck`/`shellcheck -x`, `qmllint`, `zig build test`, and the full suite.

## Acceptance

Paste real output for each:

1. `grep -rn 'koompi/koompi-hd' --exclude-dir=.git --exclude-dir=.work .` — empty.
2. `grep -rn 'koompi/desktop' --exclude-dir=.git --exclude-dir=.work .` — only the
   `koompi-desktop-history` references.
3. The remaining `koompi-desktop` occurrences, each justified as a package name, the repo, or a
   deliberate compatibility path.
4. `bash tests/test_resolve_checkout_paths.sh`, `tests/test_update_prod_branch.sh`,
   `tests/test_iso_release_tag.sh`, `tests/test_packaged_tools.sh` — rc 0.
5. The `origin_is_koompi` proof: all four URL generations accepted, a non-KOOMPI origin rejected.
6. `qmllint` 0 errors, `zig build test`, `shellcheck` + `-x`.
7. `bash tests/run.sh` tail.

## Out of scope

- The local directory `/home/userx/workspace/koompi-desktop`, which already matches and stays.
- The `v0.1` release notes and the `prod-hd` branch — the lead handles both after you land.
- Any package name, `depends=` entry, or the strings at `installer/src/archinstall.zig:31-32`.
- The 2021 archive repo.

## Stop conditions

- **The real checkout at `/home/userx/workspace/koompi-desktop` is Rithy's**, sitting on branch
  `koompi-sd` with uncommitted work. Do not touch, switch, stash or dirty it.
- An occurrence you cannot confidently classify → leave it and list it.
- Dropping a generation from the guess list would strand a checkout → stop; that is the whole risk
  of renaming twice in one day.
