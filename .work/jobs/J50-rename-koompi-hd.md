# J50 — Rename sweep: koompi/desktop → koompi/koompi-hd

Rithy, 2026-08-26: the GitHub repo is renamed from `koompi/desktop` to `koompi/koompi-hd`
("hd" = Hyprland desktop). The lead has already done the rename and re-pointed this checkout's
`origin`; GitHub redirects the old URL, so nothing is broken while you work. Your job is to make the
tree tell the truth.

The local checkout path stays `/home/userx/workspace/koompi-desktop`. Do not move it.

## The one thing you must not get wrong

`koompi-desktop` is **also a package name**. `koompi-desktop-hyprland`, `koompi-desktop-kde`,
`koompi-desktop-experience` and the transitional alias `koompi-desktop` are real `pkgname=` values
(`sdata/dist-arch/koompi-desktop-hyprland/PKGBUILD:7` and siblings), and
`installer/src/archinstall.zig:31-32` pacstraps those literals. Renaming any of them breaks installs.

Of the 74 occurrences of the string in the tree: 17 are repo identity and change, 49 are package
names and do not, 8 are something else. Classify before you edit; a blind `sed` fails this job.

## Files you own

Every file carrying a repo-identity occurrence or a `koompi/desktop` URL, including:

- `install.sh` (`:7` `REPO_URL`, `:9` `DEST`)
- `dots/.local/share/koompi/libexec/update` (`:33` `UPSTREAM_REPO`, `:34` `CLONE_DIR`, `:476-477`
  the `resolve_checkout` guess list, `:572`, `:600`, `:602` user-facing text)
- `README.md` (`:9,12,17,18,68,86`)
- `dots/.config/quickshell/koompi/modules/settings/About.qml` (`:96,123,131,138`),
  `dots/.config/quickshell/koompi/welcome.qml` (`:452,459,477,484,491`)
- `cli/src/main.zig:313`, `sdata/dist-arch/iso/koompi/airootfs/etc/os-release:18`,
  `installer/src/post_install.sh:215`
- the five PKGBUILD `url=` fields (`koompi-branding`, `koompi-kde-config`, `koompi-oem`,
  `koompi-sysdefaults`, `ttf-koompi-star`) and `koompi-branding/PKGBUILD:40,42`
- the five `$srcdir/koompi-desktop` BUILD NOTE headers (`koompi-hyprland-config:7`,
  `koompi-kde-config:11`, `koompi-session:8`, `koompi-shell:14`, `sdata/dist-arch/repo/README.md:108`)
- `tests/test_iso_release_tag.sh` (`:50`, `:68` hardcode the slug)
- `docs/agents/migrations.md:88`, `docs/agents/SKILL.md:1`,
  `dots/.config/quickshell/koompi/services/SearchBench.qml:28`

Leave alone: everything in the package-name bucket; `koompi/koompi-desktop-history` in `UPSTREAM.md:34`
and `docs/agents/contributing.md:29` (a different repo that still exists under that name); the
`docs/brainstorm/sections/*.html` mockups, which are fake screenshots.

Not yours: `sdata/install/update.sh` and the route logic in `libexec/update` below line 460 —
J51 follows you into that file and owns its behaviour.

## Do

1. Classify all 74 occurrences into repo-identity / package-name / other. Put the table in your report.
2. Change the repo-identity ones and every `koompi/desktop` URL to `koompi/koompi-hd`.
3. `resolve_checkout` (`libexec/update:471-490`): the guess list only knows `koompi-desktop*` and
   `koompi-hyprland*` directory names. Add the `koompi-hd` forms, keeping every old name — a user
   whose state file is stale must find their existing checkout, not get a second clone. The comment at
   `:474` already explains why the old names stay; extend it, do not replace it.
4. Decide and state what `CLONE_DIR` and `install.sh`'s `DEST` become. If they change, a user who
   already has `~/.local/share/koompi-desktop` must still be found by `resolve_checkout` — prove that
   in the test, because getting it wrong silently doubles a checkout on every machine.
5. `README.md:18` says `cd koompi-desktop` after cloning `koompi/desktop.git`, which was already
   wrong (that clone makes `desktop/`). Fix it to match the new name properly.
6. `tests/test_iso_release_tag.sh` is your own check: it hardcodes the slug and fails until you update
   it. Make sure it passes for the right reason, not by loosening the assertion.
7. `shellcheck`/`shellcheck -x` on the shell files, `qmllint` on the QML, `zig build test` for the CLI,
   and the full suite.

## Acceptance

Paste real output for each:

1. The classification table: 17 / 49 / 8 with the counts you actually measured.
2. `grep -rn 'koompi/desktop' --exclude-dir=.git --exclude-dir=.work .` — only the
   `koompi-desktop-history` references remain.
3. `grep -rn 'koompi-desktop' --exclude-dir=.git --exclude-dir=.work . | wc -l` and the list of what
   is left, each line justified as a package name or the history repo.
4. `bash tests/test_iso_release_tag.sh` and `bash tests/test_packaged_tools.sh`, rc 0.
5. `qmllint` on `About.qml` and `welcome.qml`, 0 errors; `zig build test` in `cli/`.
6. `shellcheck` + `shellcheck -x` on `install.sh` and `libexec/update`.
7. `bash tests/run.sh` tail.
8. The `resolve_checkout` proof: an old-name checkout is still found after the change.

## Out of scope

- Renaming the local directory, any git branch, or the `koompi-desktop-history` repo.
- The pacman repo, the release tag, `sdata/install/update.sh`.
- Rewording prose beyond what the rename requires.

## Stop conditions

- An occurrence you cannot confidently classify → leave it, list it in the report, and say why.
- A change would alter a `pkgname=`, a `depends=` entry, or the strings at
  `installer/src/archinstall.zig:31-32` → stop; that breaks installs.
- Changing `CLONE_DIR` would strand existing checkouts and you cannot prove otherwise → keep the old
  value and report it.
