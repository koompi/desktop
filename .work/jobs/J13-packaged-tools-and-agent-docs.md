# J13 — packaged install misses five koompi-* tools; agent docs deny two of them

From `.work/OMARCHY-AUDIT.md` O01 and O20, both verified by the lead 2026-08-25:
- `sdata/dist-arch/koompi-shell/PKGBUILD:58-64` installs 13 named tools. `dots/.local/bin/` also has
  `koompi-hook`, `koompi-plugin`, `koompi-webapp-install`, `koompi-notify-send`, `koompi-logout`, which the
  CLI (`cli/src/main.zig:25-28`) and the shell call. On KOOMPI OS `koompi hook` and `koompi plugin` fail.
- `docs/agents/hooks.md:3` and `docs/agents/plugins.md:15` say those commands do not exist. They do.

## Files you own
- `sdata/dist-arch/koompi-shell/PKGBUILD`
- new `tests/test_packaged_tools.sh`
- `docs/agents/hooks.md`, `docs/agents/plugins.md`
- `.work/J13-report.md`

## Do
1. (O01) Make the PKGBUILD install every `dots/.local/bin/koompi-*` executable instead of a hand list, keeping
   any deliberate exclusions explicit in a named array with a comment saying why each is excluded. Read every
   tool's header first; if one is dev-only or references a repo path, that is an exclusion candidate.
2. (O01) `tests/test_packaged_tools.sh`, in the style of the existing `tests/test_*.sh`: parse the PKGBUILD
   (source it under `set -u` in a subshell or grep the array) and fail if any `dots/.local/bin/koompi-*`
   executable is neither installed nor in the exclusion list, and if any listed name has no file.
3. (O20) Rewrite the two docs to describe what `koompi-hook` and `koompi-plugin` actually do today, from their
   source (`dots/.local/bin/koompi-hook`, `koompi-plugin`), with the event list and the plugin layout. Keep
   the docs' existing structure and voice; state plainly anything still unimplemented, citing the file.
4. Build the package: `cd sdata/dist-arch/koompi-shell && makepkg -f --nodeps` (no install, no sudo) and list
   the package's `usr/bin` contents from the built `.pkg.tar.zst` with `bsdtar -tf`.

## Acceptance
1. Paste `bsdtar -tf <pkg> | grep usr/bin/` from the built package: every `koompi-*` tool present, exclusions
   accounted for by name.
2. Paste the test failing when you temporarily add a fake `dots/.local/bin/koompi-zzz` executable, then
   passing after removing it.
3. Paste `./tests/run.sh` tail: baseline plus one, 0 failed; `shellcheck tests/test_packaged_tools.sh` clean;
   `namcap` on the PKGBUILD if installed (say so if not).
4. Paste the first 15 lines of each rewritten doc.

## Out of scope
- Any change to the tools themselves or the CLI.
- Other PKGBUILDs; the `[koompi]` repo.
- Installing the package (needs sudo; the lead does that).

## Stop conditions
- A tool whose header says it must not ship (dev-only, repo-relative): exclude, explain in the report, do not
  rewrite it.
- `makepkg` needing a package that is not installed: name it and stop.
