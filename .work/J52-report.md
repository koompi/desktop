# J52 report — rename sweep koomi/koomi-hd → koomi/koompi-desktop

Branch `j52-rename-back`, two commits: `4fd2dfbb` (identity sweep, 21 files) and
`4e8cd47f` (origin generations + test extensions, 4 files). Not pushed.
No stop condition hit: no pkgname= and no depends= entry changed;
installer/src/archinstall.zig is absent from both commits (git diff HEAD --stat on it
is empty) and lines 31-32 still read `.hyprland => "koompi-desktop-hyprland"`,
`.kde => "koompi-desktop-kde"`.

## Counting basis

Same convention as J50: tracked files, line-granular. Today the tracked tree carries
131 occurrences on 122 lines containing `koompi-desktop` (the tree grew since J50's count:
the v0.1 release work landed). Buckets below are per line.

## Acceptance 1 — old hd slug gone from live references

```
$ grep -rn 'koompi/koompi-hd' --exclude-dir=.git --exclude-dir=.work .
rc=1 (no matches)
```

Empty. The hd-era slug survives only inside origin_is_koompi's alternation
(`koompi/(desktop|koompi-hd|koompi-desktop)`), where the alternation paren keeps the
contiguous literal from ever appearing, and in test comments that document history —
both required by Do #4/#5 and verified by the mechanical scan below.

## Acceptance 2 — pre-J50 slug

```
$ grep -rn 'koompi/desktop' --exclude-dir=.git --exclude-dir=.work .
./sdata/install/update.sh:26:    # Every slug this repo has ever carried: koompi/desktop is what machines
./tests/test_update_prod_branch.sh:152:# The repo was renamed twice on 2026-08-26: koompi/desktop, then the one-day
rc=0
```

Two lines, both comments documenting the generation history that Do #4 requires
accepting. No URL, clone source, or remote points there. The koompi-desktop-history
references (UPSTREAM.md:34, docs/agents/contributing.md:29) are intact and do not
contain this substring.

## Acceptance 3 — remaining koompi-desktop occurrences, classified

Mechanical scan over all tracked files (script, not eyes - reason recorded under
"Incident"):

```
WITH-p 'koompi-desktop' occurrences: 134 across 43 tracked files
NO-p  stragglers: 0
files containing bare no-p short-form org: none
```

Line-level buckets (122 lines):

| Bucket | Lines | Justification |
| --- | --- | --- |
| Repo identity | 60 | README one-liners/clone/cd prose, install.sh REPO_URL+DEST, About/welcome screens, libexec/update UPSTREAM_REPO+CLONE_DIR+die texts, cli/src/main.zig bootstrap hint, os-release + post_install BUG_REPORT_URL, five PKGBUILD url= fields, branding release comments, five $srcdir BUILD NOTEs, repo/README note, iso-release-tag test slug |
| Package names (untouched) | 35 | archinstall.zig (incl. lines 31-32), config.zig, theme.zig, koompi.toml, installer/README, ui-ux.md, build-packages.yml, install-deps.sh, packages.x86_64, iso README, and the pkgname=/depends= lines of the koompi-desktop, -experience, -hyprland, -kde PKGBUILDs plus pkgname lines of the config/session/shell/sysdefaults/oem/star PKGBUILDs |
| Deliberate compat/tests | 19 | origin_is_koompi alternation + comment, resolve-checkout guess-list entries naming every generation, both test files' fixtures/assertions spelling legacy names to test them |
| Other: mockup HTML | 6 | docs/brainstorm fake screenshots, untouched since J50 |
| Other: history repo | 2 | UPSTREAM.md:34, docs/agents/contributing.md:29 |

Unclassifiable occurrences: none.

## Acceptance 4 — named shell tests

```
$ nice -n 19 ionice -c 3 bash tests/test_resolve_checkout_paths.sh ; echo rc=$?
ok: resolve_checkout finds checkouts under every name the repo has had
rc=0
$ nice -n 19 ionice -c 3 bash tests/test_update_prod_branch.sh ; echo rc=$?
PASS: a managed checkout on main moves to prod-hd
PASS: a checkout already on prod-hd just pulls
PASS: a checkout carrying its own commit is left alone
PASS: a dirty checkout is left alone
PASS: a clean, fully pushed feature branch is left alone
PASS: a checkout whose origin is not the KOOMPI repo is left alone
PASS: every origin generation a real machine can have is still the KOOMPI repo
PASS: the opt-out keeps a checkout on main until it is taken back
PASS: a dry run moves nothing
PASS: no origin/prod-hd yet means an ordinary, silent update
PASS: a shallow single-branch checkout moves and keeps pulling
PASS: a local prod-hd branch of somebody's own is not taken over
PASS: an update re-runs the installer code it just pulled
PASS: the re-exec happens at most once
PASS: an update that pulled nothing runs straight through
PASS: run_update re-runs from the pulled tree, after the pull
PASS: every option setup takes survives the re-exec
PASS: install.sh clones prod-hd when the remote has it
PASS: install.sh falls back to main when the remote has no prod-hd
PASS: KOOMPI_REF still overrides the choice
PASS: a re-run over an existing checkout stays on prod-hd
rc=0
$ nice -n 19 ionice -c 3 bash tests/test_iso_release_tag.sh ; echo rc=$?
ok: same-day ISO builds get distinct tags and a re-run replaces its own assets
rc=0
$ nice -n 19 ionice -c 3 bash tests/test_packaged_tools.sh ; echo rc=$?
packaged tools: 38 shipped, 2 excluded, all accounted for
rc=0
```

## Acceptance 5 — origin_is_koompi proof

Real function sourced from sdata/install/update.sh against a real git remote (harness
re-points origin per case):

```
ok       accept git@github.com:koompi/desktop.git              pre-2026-08-26 era
ok       accept https://github.com/koompi/desktop
ok       accept https://github.com/koompi/desktop/
ok       accept git@github.com:koompi/koompi-hd.git       one-day window
ok       accept https://github.com/koompi/koompi-hd
ok       accept https://github.com/koompi/koompi-desktop.git   current
ok       accept git@github.com:koompi/koompi-desktop
ok       accept https://github.com/koompi/koompi-desktop/
ok       reject https://github.com/someone/koompi-desktop.git
ok       reject git@github.com:someoneelse/desktop.git
ok       reject /home/somebody/elsewhere/repo.git
verdict: 11 correct, 0 mismatches
```

Do #4 verdict: the inherited pattern accepted only the hd and current slugs; machines
with the pre-rename koompi/desktop origin were disowned. Fixed; the generations case in
test_update_prod_branch.sh pins it.

Mutation check - reverting the function to the two-slug form makes the new case fail
with exactly the false negative Do #4 warns about:

```
FAIL: an origin at git@github.com:koompi/desktop.git was disowned
```

Mutation check for Do #5 - deleting the koompi-hd guesses from resolve_checkout's list makes
the new scenario fail with exactly the double clone:

```
FAIL: expected the koompi-hd checkout, got:
==> Cloning the desktop checkout
     $ git clone --recursive https://github.com/koompi/koompi-desktop /home/userx/.tmp/tmp.Vh2oiNZDEu/hd-window/.local/share/koompi-desktop
```

(That failing run also side-confirms the GitHub redirect serves the renamed repo.)
Both mutations were reverted; restored trees pass.

## Acceptance 6 — QML, CLI, shellcheck

Repo-convention qmllint (/usr/lib/qt6/bin/qmllint, fail on ^Error):

```
$ /usr/lib/qt6/bin/qmllint -I dots/.config/quickshell \
    dots/.config/quickshell/koompi/modules/settings/About.qml ; echo rc=$?
rc=0          (0 errors)
$ /usr/lib/qt6/bin/qmllint -I dots/.config/quickshell \
    dots/.config/quickshell/koompi/welcome.qml ; echo rc=$?
rc=0          (0 errors)
SearchBench.qml: qmllint output grep -c '^Error' = 0
$ cd cli && nice -n 19 ionice -c 3 zig build test --summary all
Build Summary: 3/3 steps succeeded; 3/3 tests passed
test success
+- run test 3 pass (3 total) 6ms MaxRSS:4M
```

```
shellcheck install.sh                              clean
shellcheck -x install.sh                           clean
shellcheck -x dots/.local/share/koompi/libexec/update   clean
shellcheck sdata/install/update.sh                 clean
shellcheck tests/test_update_prod_branch.sh        clean
shellcheck tests/test_resolve_checkout_paths.sh    clean
```

Plain non-x shellcheck of libexec/update still emits the pre-existing SC1091 info on
line 38's source directive, same as at HEAD; line untouched by this job.

## Acceptance 7 — full suite

```
$ nice -n 19 ionice -c 3 bash tests/run.sh     # tail
  ok test_zig_build_abort.sh

102 passed, 3 skipped, 0 failed
skipped: test_globalmenu.sh test_hypridle_logged.sh test_search_bench_parity.sh
rc=0
```

Includes the extended test_resolve_checkout_paths.sh and test_update_prod_branch.sh.

## Decision taken (job Do #2/#3)

CLONE_DIR and install.sh DEST are back to $HOME/.local/share/koompi-desktop (XDG_DATA_HOME
respected), which is also what installs from before today already have on disk - so
the common pre-rename machine resolves through CLONE_DIR even with no state file. The
guess list leads with the current name and keeps the koompi-hd forms first-class after it
(scenario 2 of the resolve test proves an hd-only machine is found, never cloned
over); koompi-hyprland and koompi-os remain for older generations. PROD_REF stays
prod-hd (branch names are the lead's territory).

## Incident worth recording: the one-letter hunt

`koom` + i vs `koom` + p + i differ by one glyph, and most of this session's debugging
burned on hand-typed probes whose own needles carried that class of typo. The initial
pattern rewrite dropped a letter from the acceptance alternation, which made the
prod-branch suite reject fixture origins; because probe scripts kept re-introducing
near-identical strings, results looked like a nondeterministic regexec bug ("same
bytes, different answers"). It never was: byte-exact comparison (od, python ord
tables, fnmatch simulation) showed every result was correct for the actual bytes.
Final state was verified without eyes: a python token audit of every occurrence in all
changed files (zero stragglers in the tracked tree) plus the two mutation proofs above.

Second catch by the ratchet: the longer guess-list comment grew libexec/update to 697
lines against the 695 allow-list entry; compressed to 694 (test_file_length ok: 942
files under cap, 34 allow-listed and not grown).

## Ownership deviation, flagged

tests/test_update_prod_branch.sh is not in the contract's file list, but Acceptance 1
demands a tree-wide empty grep for the dead slug and that file's fixture origins
carried it five times. Its fixtures were renamed (semantics unchanged: still "a
KOOMPI-shaped origin"), and the Do #4 runnable check lives there as the generations
case. No other job owns it (J51 closed).

## Out-of-scope left alone

The real checkout at /home/userx/workspace/koompi-desktop (never touched), v0.1 release notes
and the prod-hd branch (lead), all package names and archinstall.zig lines 31-32, the
2021 archive repo, the koompi-desktop-history references, mockup HTML, branch names.
