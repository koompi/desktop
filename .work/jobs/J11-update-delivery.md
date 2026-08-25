# J11 — `koompi update` does not deliver what the tree has

Evidence, 2026-08-25. A user ran `koompi update` and their sidebar
(`~/Pictures/Screenshots/2026-08-25/users-koompi-os.jpg`) lacks what the dev machine shows.
Three causes found in the tree; verify each before fixing:

- B1 Packaged route delivers nothing of ours. `dots/.local/share/koompi/libexec/update:` `is_packaged` →
  `pacman -Syu` → "packages up to date". The `[koompi]` repo is a skeleton
  (`sdata/dist-arch/repo/README.md:20-22`, `sdata/dist-arch/iso/koompi/pacman.conf:18-28` disabled,
  `.github/workflows/build-packages.yml` manual-only, sign/publish commented out). Nothing serves
  `koompi-shell` (`pkgver=1.1` static) so a packaged user never receives a change we commit, and the
  command still says up to date.
- B2 Config defaults never reach existing users. The shell writes `~/.config/koompi/config.json` in full at
  first run (JsonAdapter), `dots/` ships no `config.json`, and `sdata/install/files.sh` rsyncs without
  touching it. So a default changed in `modules/common/Config.qml` after a user's first run is invisible to
  them forever. Concrete: `Config.qml:724-729` `quickSliders.enable: false` is the shipped default; the dev
  machine has it `true`; the user's screenshot has no sliders.
- B3 Shipped defaults differ from the dev machine's config (same file). Which of those differences are
  intended product defaults is Rithy's call; you produce the list, you do not change defaults.

## Files you own
- `dots/.local/share/koompi/libexec/update`
- `sdata/install/update.sh`, `sdata/install/files.sh`
- `dots/.local/bin/koompi-migrate`
- new: `tests/test_update_route.sh`, `tests/test_config_merge.sh`, any helper script under `dots/.local/share/koompi/libexec/`
- `docs/` page on updating, if one exists
- `.work/J11-report.md`, `.work/J11-config-diff.md`

Not yours: `modules/common/Config.qml` (read only; do not change defaults), `cli/src/` (no new subcommand
unless nothing else can work; if so, stop and say why).

## Do
1. (B1) In `libexec/update`, after the packaged upgrade, decide honestly whether anything of ours could have
   moved: `pacman-conf --repo-list` contains `koompi`, or the koompi-* versions before/after differ. If neither,
   say so in one line and run the git route instead: use `~/.local/state/koompi/repo-path` if present, else
   clone `https://github.com/koompi/desktop` to `~/.local/share/koompi-desktop`, record the path, and run
   `./setup update` with the same `--yes/--dry-run` flags. The output must name which route ran. "packages up
   to date" alone is never the last word on a machine with no `[koompi]` repo.
2. (B2) Three-way merge of config defaults on update. Old defaults = defaults as shipped by the tree the user
   had before this update (from-git: dump them from the checkout *before* `git pull`; packaged: from the
   previously installed `/etc/xdg/quickshell/koompi` tree, saved to `~/.local/state/koompi/config-defaults.json`
   on every update). New defaults = same dump from the new tree. For every leaf: user == old default and new
   default differs → apply new default; user != old default → keep user; leaf new in defaults → add. Back up
   `config.json` to `config.json.bak-<YYYYmmdd-HHMMSS>` before writing, write via temp + `mv`, validate with
   `jq -e 'type == "object"'`. You need a way to dump defaults from a tree without a running shell: a small
   `qs -p` script pointed at a temp `XDG_CONFIG_HOME` that loads the tree's `Config` singleton and exits after
   it writes is the obvious one; document whatever you pick in the script header. No previous snapshot on a
   packaged machine → take the snapshot, apply nothing, print that defaults are tracked from now on.
3. (B3) Write `.work/J11-config-diff.md`: every leaf where `/home/userx/.config/koompi/config.json` differs
   from the shipped defaults, as `path | shipped | dev machine`. Do not change any default.
4. Fresh-user check: `HOME=$(mktemp -d) ./setup update --dry-run` is not enough; do a real files-only
   install into a temp HOME (see `parse_install_options` in `setup` for the flag) and diff the result against
   `dots/` — every file in `dots/` must land. Paste the count of files copied and the diff (expect empty apart
   from the documented excludes in `files.sh`).
5. Tests. `tests/test_update_route.sh`: a PATH shim `pacman`/`pacman-conf` that reports koompi-shell installed
   and no koompi repo; `koompi update --dry-run` must print the git fallback. `tests/test_config_merge.sh`: old
   `{a:1,b:2}`, user `{a:1,b:3}`, new `{a:9,b:5,c:7}` → `{a:9,b:3,c:7}`; plus the backup file exists and the
   original is untouched on a failed write. Both in the style of the existing `tests/test_*.sh`.
6. `shellcheck` every script you touched; `./tests/run.sh`.

## Acceptance
1. Paste `koompi update --dry-run` output on this machine (from-git route) tail, and the shimmed packaged run
   showing the fallback line.
2. Paste the merge test run with its input/output JSON.
3. Paste `.work/J11-config-diff.md`.
4. Paste the fresh-HOME install file count and the diff against `dots/`.
5. `./tests/run.sh` tail: baseline 56 passed plus your new tests, 0 failed; shellcheck clean on touched files.
6. `.work/J11-report.md`: what each of B1-B3 turned out to be, the diff summary, anything you could not verify.

## Out of scope
- Publishing or signing the `[koompi]` repo, the ISO, `koompi-installer` (J12).
- Changing any shipped default in `Config.qml`.
- `koompi-migrate`'s skel sync semantics beyond adding the config-merge step.
- Touching Rithy's real `~/.config/koompi/config.json`; test against copies.

## Stop conditions
- Any path that writes a user's `config.json` without a backup first.
- Needing `sudo` or a new package.
- If old defaults cannot be obtained on some route, stop and report the route rather than guessing.
