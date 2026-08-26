# J50 report — rename sweep koompi/desktop → koompi/koompi-hd

Branch `j50-rename-koompi-hd`, two commits (`06357bc7` sweep, `caa2c9b8` test).
No stop condition hit: no `pkgname=`, no `depends=` entry, and neither string at
`installer/src/archinstall.zig:31-32` was touched (the file is absent from both commits).

## Counting basis

Measured on tracked files, excluding the worktree's `.git` pointer file (a one-line
gitdir reference whose path happens to contain the string; it is checkout plumbing,
not content). With that exclusion the tree has **exactly 74 matching lines**, and the
lead's split reproduces: **17 repo identity / 49 package name / 8 other**.
(Counting occurrences instead of lines gives 83 — several lines carry the string twice;
the buckets below are per line, which is what sums to 74.)

Independently, all **27 lines carrying the `koompi/desktop` slug** were repo identity and
all 27 changed to `koompi/koompi-hd`.

## Acceptance 1 — classification table

**Repo identity — changed (17):**

| Where | Lines | What |
| --- | --- | --- |
| `README.md` | 12, 18 | managed-checkout path in prose, `cd` after clone |
| `install.sh` | 9 | `DEST` default |
| `dots/.local/share/koompi/libexec/update` | 34, 572, 600, 602 | `CLONE_DIR`, two `die` texts, record-the-path example |
| `dots/.local/share/koompi/libexec/update` | 476, 477 | guess-list lines: old names kept verbatim, `koompi-hd` forms added ahead (comment extended, not replaced) |
| `docs/agents/SKILL.md` | 1 | title |
| `docs/agents/migrations.md` | 88 | example checkout path |
| `sdata/dist-arch/koompi-hyprland-config/PKGBUILD` | 7 | BUILD NOTE `$srcdir` |
| `sdata/dist-arch/koompi-kde-config/PKGBUILD` | 11 | BUILD NOTE `$srcdir` |
| `sdata/dist-arch/koompi-session/PKGBUILD` | 8 | BUILD NOTE `$srcdir` |
| `sdata/dist-arch/koompi-shell/PKGBUILD` | 14 | BUILD NOTE `$srcdir` |
| `sdata/dist-arch/repo/README.md` | 108 | BUILD NOTE `$srcdir` |

The four PKGBUILD BUILD NOTEs say `$srcdir/koompi-hd/dots` now because a clean-chroot
source switch pins a tag of the renamed repo, and makepkg extracts a clone of
`koompi/koompi-hd` under that name; there is no `source=` array relying on the old
string today (in-tree builds read `../../../dots` via `$startdir`).

**Slug `koompi/desktop` — changed (27 lines):**
`README.md` 9, 17, 68, 86 · `install.sh` 7 · `About.qml` 96, 123, 131, 138 ·
`welcome.qml` 452, 459, 477, 484, 491 · `libexec/update` 33 (`UPSTREAM_REPO`) ·
`installer/src/post_install.sh` 215 · `airootfs/etc/os-release` 18 ·
`koompi-branding/PKGBUILD` 20, 40, 42 · `koompi-kde-config/PKGBUILD` 18 ·
`koompi-oem/PKGBUILD` 16 · `koompi-sysdefaults/PKGBUILD` 18 ·
`ttf-koompi-star/PKGBUILD` 24 · `tests/test_iso_release_tag.sh` 50, 68 ·
`cli/src/main.zig` 313.

**Package names — untouched (49 lines):**
`README.md` 147 (`koompi-desktop-experience`) · `.github/workflows/build-packages.yml` 56 ·
`installer/README.md` 56, 82, 83 · `installer/themes/koompi.toml` 98, 102, 107 ·
`installer/src/theme.zig` 269 · `installer/src/archinstall.zig` 28, **31, 32** ·
`installer/src/config.zig` 12, 13 · `installer/docs/ui-ux.md` 364, 378, 385, 403, 458,
816, 905, 946, 955, 982, 984 · `sdata/dist-arch/install-deps.sh` 5 ·
`sdata/dist-arch/koompi-hyprland-config/PKGBUILD` 15 ·
`sdata/dist-arch/koompi-desktop-hyprland/PKGBUILD` 1, 5, 7 ·
`sdata/dist-arch/koompi-desktop-kde/PKGBUILD` 1, 4, 6 ·
`sdata/dist-arch/koompi-desktop-experience/PKGBUILD` 1, 2, 8, 17, 22 ·
`sdata/dist-arch/koompi-desktop/PKGBUILD` 1, 3, 4, 5, 7, 13 ·
`sdata/dist-arch/iso/koompi/README.md` 8, 24, 78 ·
`sdata/dist-arch/iso/koompi/packages.x86_64` 4 · `sdata/dist-arch/repo/README.md` 93.

**Other — untouched (8 lines):**
`UPSTREAM.md` 34 and `docs/agents/contributing.md` 29 (`github.com/koompi/koompi-desktop-history`,
a different repo that still exists under that name) · fake-screenshot mockups
`docs/brainstorm/sections/02-shell-bar.html` 40, 68, 1008 ·
`46-clipboard-manager.html` 102, 110 · `26-index-status.html` 43.

Unclassifiable occurrences: none.

## Acceptance 2 — old slug gone

```
$ grep -rn 'koompi/desktop' --exclude-dir=.git --exclude-dir=.work .
rc=1 (no matches)
```

Zero lines remain — including the history-repo references: `koompi/koompi-desktop-history`
does not contain the substring `koompi/desktop`, so those two lines never matched this
pattern; they are intact and listed under Other above.

## Acceptance 3 — what still contains `koompi-desktop`

Raw command, pasted as specified:

```
$ grep -rn 'koompi-desktop' --exclude-dir=.git --exclude-dir=.work . | wc -l
1241
```

1241 is polluted: running `tests/run.sh` built Rust/Zig artefacts into gitignored
`shell-services/target/`, `globalmenu/target/`, `cli/.zig-cache/`, `audiod/.zig-cache/`
and their absolute paths contain this worktree's directory name (`.../koompi-desktop/j50-rename-koompi-hd/...`).
They are untracked build output, not tree content. Tracked files only:

```
$ git grep -n 'koompi-desktop' -- ':(exclude).work' | wc -l
68
```

Justified: 49 package-name lines (list in Acceptance 1, unchanged) + 8 other lines
(history repo and mockups, unchanged) + 11 deliberate legacy-name references:
`libexec/update` guess-list entries and the comment explaining why the old names stay (3),
and fixture paths/assertions in `tests/test_resolve_checkout_paths.sh` (8), which must
spell the old directory names to test them.

## Acceptance 4 — named shell tests

```
$ nice -n 19 ionice -c 3 bash tests/test_iso_release_tag.sh ; echo rc=$?
ok: same-day ISO builds get distinct tags and a re-run replaces its own assets
rc=0
$ nice -n 19 ionice -c 3 bash tests/test_packaged_tools.sh ; echo rc=$?
packaged tools: 38 shipped, 2 excluded, all accounted for
rc=0
```

`test_iso_release_tag.sh` passes for the right reason: it now sets
`GITHUB_REPOSITORY=koompi/koompi-hd` and asserts `--repo koompi/koompi-hd` reaches `gh`;
the assertion was tightened to the new slug, not loosened.

## Acceptance 5 — QML and CLI

The `qmllint` on PATH is Qt5-era ("qmllint 1.0") and exits 255 with zero output even on
unmodified HEAD (verified) — unusable here. The repo's own convention
(`tests/test_fingerprint_setup.sh:250-259`) is `/usr/lib/qt6/bin/qmllint`, failing on
`^Error`; warnings are tolerated. Used that, with `-I dots/.config/quickshell` so the
`qs.*` imports resolve:

```
$ /usr/lib/qt6/bin/qmllint -I dots/.config/quickshell \
    dots/.config/quickshell/koompi/modules/settings/About.qml ; echo rc=$?
rc=0          # errors=0, warnings=58
$ /usr/lib/qt6/bin/qmllint -I dots/.config/quickshell \
    dots/.config/quickshell/koompi/welcome.qml ; echo rc=$?
rc=0          # errors=0, warnings=170
```

0 errors on both; the warnings are import/unqualified-access notices that exist at HEAD too.

```
$ cd cli && nice -n 19 ionice -c 3 zig build test --summary all
Build Summary: 3/3 steps succeeded; 3/3 tests passed
test success
+- run test 3 pass (3 total) 7ms MaxRSS:4M
   +- compile test Debug native success 511ms MaxRSS:146M
```

## Acceptance 6 — shellcheck

```
$ shellcheck install.sh            → rc=0 (no output)
$ shellcheck -x install.sh         → rc=0 (no output)
$ shellcheck dots/.local/share/koompi/libexec/update
In dots/.local/share/koompi/libexec/update line 38:
source "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/update-lib.sh" \
       ^-- SC1091 (info): Not following: update-lib.sh was not specified as input (see shellcheck -x).
rc=1
$ shellcheck -x dots/.local/share/koompi/libexec/update → rc=0 (no output)
```

The SC1091 info is pre-existing — plain shellcheck on the HEAD version of the file
returns 1 with the same note (line 38 is untouched by this job); `-x`, which follows the
source directive, is clean.

## Acceptance 7 — full suite

```
$ nice -n 19 ionice -c 3 bash tests/run.sh     # tail
  ok test_zig_build_abort.sh

100 passed, 3 skipped, 0 failed
skipped: test_globalmenu.sh test_hypridle_logged.sh test_search_bench_parity.sh
rc=0
```

Includes the new `tests/test_resolve_checkout_paths.sh`.

## Acceptance 8 — resolve_checkout proof

New test (`tests/test_resolve_checkout_paths.sh`) sources the real script with its library
guard and its real defaults, then pins five scenarios: pre-rename checkout found and not
re-cloned, bare legacy name found, new name found, current name preferred when both exist,
state file beats every guess.

```
$ nice -n 19 ionice -c 3 bash tests/test_resolve_checkout_paths.sh ; echo rc=$?
ok: resolve_checkout still finds pre-rename checkouts and never re-clones one
rc=0
```

Mutation check — deleting the `koomi-desktop` guesses from a scratch copy makes it fail
with exactly the double-clone the job warns about:

```
FAIL: expected the pre-rename checkout, got:
==> Cloning the desktop checkout
  -> packages alone cannot deliver KOOMPI updates here, ...
     $ git clone --recursive https://github.com/koompi/koompi-hd
       /home/userx/.tmp/tmp.gQ9V7GrRkv/pre-rename/.local/share/koompi-hd
```

(Side confirmation: the clone in that failure run fetched the real renamed upstream.)

## Decision taken (job Do #4)

`CLONE_DIR` and `install.sh DEST` are now `${XDG_DATA_HOME:-$HOME/.local/share}/koompi-hd`
and `$HOME/.local/share/koompi-hd`. A user with an existing `~/.local/share/koompi-desktop`
is still resolved — state file first, and `~/.local/share/koompi-desktop` remains in the
guess list, checked before any clone happens — proven in Acceptance 8. The dev checkout at
`/home/userx/workspace/koompi-desktop` was not moved. `README.md:18` is `cd koompi-hd`,
which also fixes the pre-existing lie (a clone of `koompi/desktop.git` never produced
`koompi-desktop/`). Re-running the bootstrap one-liner on an old install creates the new
directory rather than adopting the old one — bootstrap has always behaved that way for a
moved `DEST`, and `koompi update` (J51's territory) is the supported path for existing
installs.

## Out-of-scope items left alone

Local directory, branch name, `koompi-desktop-history` repo, pacman repo, release tag,
`sdata/install/update.sh`, route logic in `libexec/update` beyond the owned lines,
mockup HTML, prose beyond the rename.
