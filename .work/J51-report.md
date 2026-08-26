# J51 report — `koompi update` follows `prod-hd`, and runs the code it pulled

Branch `j51-prod-hd-branch`, six commits. Round 2 folded in.
Files touched: `install.sh`, `sdata/install/update.sh`, new `tests/test_update_prod_branch.sh`,
`docs/agents/SKILL.md`, `.github/workflows/tests.yml`, `.github/workflows/installer.yml`, this report.
`dots/.local/share/koompi/libexec/update` was read and not edited: both routes reach `update_pull`
through `"$repo/setup" update`, so nothing there needed restructuring.

Two items beyond the original brief are in here:

- the lead's addendum, J49 F1 — an update ran the installer code it sourced before its own pull.
  Fixed in `rerun_from_pulled_tree`; item 9.
- round 2's hazard — `install.sh` defaulting to a branch that does not exist yet would have killed
  the public one-liner. Fixed in `install.sh` itself, not by an ordering instruction; item 10.

## The rule, which is the deliverable

A checkout is **managed** when it is the one this machine updates from and it carries nothing of its
own. All of these must hold before `./setup update` moves it onto `prod-hd`:

| | check | why it is there |
| --- | --- | --- |
| 1 | the tree is clean | `update_pull` already refuses a dirty tree; the move sits behind that refusal |
| 2 | HEAD is on a branch, and that branch is `main` | a developer on their own branch is never touched, even when it is clean and fully pushed |
| 3 | `origin` is the KOOMPI repo (`koompi/koompi-hd`, or `koompi-desktop` pre-rename) | a fork or a mirror is somebody's own line of work |
| 4 | the branch tracks an upstream | without one there is nothing to compare against |
| 5 | `git merge-base --is-ancestor HEAD @{u}` | one unpushed commit is enough to leave the tree alone |
| 6 | `origin/prod-hd` exists (`ls-remote`) | before the lead pushes it, and offline, this is false and the update is exactly today's, silently |
| 7 | any local `prod-hd` is contained in `origin/prod-hd` | a local branch that only shares the name is somebody's own |
| 8 | the opt-out is not set | `KOOMPI_FOLLOW_PROD=0` for a run, `git config koompi.followprod false` for good; `KOOMPI_FOLLOW_PROD=1` overrides the config back |

Anything else: leave it alone, do what today did, say why in one line. Check 6 is the only silent one.

Rule 2 is the answer to the stop condition *"your rule set would still move a developer's tree in
some case you can construct"*. Without it, a developer sitting on a clean, fully pushed feature
branch of the KOOMPI repo passes checks 1 and 3-8 and gets switched to `prod-hd`. Restricting the
move to `main` closes that; the remaining case, a developer on a clean `main`, is the one the brief
itself frames the opt-out around, and it loses nothing, since everything there is pushed.

Two things the brief did not name that the fixtures forced:

- `install.sh` clones `--depth 1 --branch <ref>`, so a real machine has `prod-hd` in neither
  `remote.origin.fetch` nor its history. `git checkout -b prod-hd --track origin/prod-hd` fails there
  with *"starting point 'origin/prod-hd' is not a branch"*. The refspec is added and the branch fetched.
- On a shallow clone, checking out a `prod-hd` that is behind the grafted tip leaves a later
  `pull --ff-only` unable to fast-forward: the graft cut the parent it needs. A one-time
  `fetch --unshallow` (35 MiB for this repo, 485 commits) precedes the switch. Pinned by the
  "shallow single-branch checkout" case, which fails without it.

## Acceptance

### 1. `bash tests/test_update_prod_branch.sh` — every PASS, rc 0

```
PASS: a managed checkout on main moves to prod-hd
PASS: a checkout already on prod-hd just pulls
PASS: a checkout carrying its own commit is left alone
PASS: a dirty checkout is left alone
PASS: a clean, fully pushed feature branch is left alone
PASS: a checkout whose origin is not the KOOMPI repo is left alone
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
```

rc 0. Twenty cases: eleven on the branch rule, five on the re-exec, four on `install.sh`.

### 2. The fixture transcript for the developer-checkout case

Three shapes of developer tree, each left where it was. `git status -sb` is printed before and after.

```
############ CASE A: a developer's checkout, one local commit, dirty tree
--- before
  $ git status -sb  ->  ## my-feature
6b4566c my work
--- ./setup update (update_pull)

==> Updating the checkout
  !! the checkout has uncommitted changes, so pulling could lose them
  -> commit or stash them, then re-run; installing from the tree as it stands
--- after
  $ git status -sb  ->  ## my-feature
6b4566c my work

############ CASE A2: same developer, edit committed and branch pushed
--- before
  $ git status -sb  ->  ## my-feature...origin/my-feature
987b3bf scratch
--- ./setup update (update_pull)

==> Updating the checkout
  -> on 'my-feature', not main: leaving this checkout on its own branch
     $ git -C "/home/userx/.tmp/tmp.nOUpMgCzQe/a/dev" pull --ff-only
Already up to date.
     $ git -C /home/userx/.tmp/tmp.nOUpMgCzQe/a/dev submodule update --init --recursive
  ok already up to date at 987b3bf6
--- after
  $ git status -sb  ->  ## my-feature...origin/my-feature
987b3bf scratch

############ CASE A3: a developer on main with one commit not yet pushed
--- before
  $ git status -sb  ->  ## main...origin/main [ahead 1]
d160148 not pushed yet
--- ./setup update (update_pull)

==> Updating the checkout
  -> 'main' carries commits upstream does not have: leaving this checkout on it
     $ git -C "/home/userx/.tmp/tmp.nOUpMgCzQe/a/dev-main" pull --ff-only
Already up to date.
     $ git -C /home/userx/.tmp/tmp.nOUpMgCzQe/a/dev-main submodule update --init --recursive
  ok already up to date at d1601489
--- after
  $ git status -sb  ->  ## main...origin/main [ahead 1]
d160148 not pushed yet
```

### 3. The no-`prod-hd`-yet case

An ordinary update: it pulls, and the word `prod-hd` never appears.

```
############ CASE B: origin has no prod-hd yet (every machine, today)
--- before
  $ git status -sb  ->  ## main...origin/main [behind 1]
24f2d56 v1
--- ./setup update (update_pull)

==> Updating the checkout
     $ git -C "/home/userx/.tmp/tmp.nOUpMgCzQe/b/machine" pull --ff-only
Updating 24f2d56..d346a8c
Fast-forward
 file | 2 +-
 1 file changed, 1 insertion(+), 1 deletion(-)
     $ git -C /home/userx/.tmp/tmp.nOUpMgCzQe/b/machine submodule update --init --recursive
  ok updated 24f2d564 -> d346a8c4
  -> 1 new commit(s)
--- after
  $ git status -sb  ->  ## main...origin/main
d346a8c v2
--- lines mentioning prod-hd:      0
--- lines reading as an error/warn: 0
```

For contrast, the managed checkout on the same fixture origin:

```
############ CASE C: a managed checkout, for contrast
--- before
  $ git status -sb  ->  ## main...origin/main
--- ./setup update (update_pull)

==> Updating the checkout
     $ git -C /home/userx/.tmp/tmp.nOUpMgCzQe/a/managed fetch --quiet origin +refs/heads/prod-hd:refs/remotes/origin/prod-hd
     $ git -C /home/userx/.tmp/tmp.nOUpMgCzQe/a/managed checkout -b prod-hd --track origin/prod-hd
Switched to a new branch 'prod-hd'
branch 'prod-hd' set up to track 'origin/prod-hd'.
  ok moved from 'main' to prod-hd, the line KOOMPI releases from
     $ git -C "/home/userx/.tmp/tmp.nOUpMgCzQe/a/managed" pull --ff-only
Already up to date.
     $ git -C /home/userx/.tmp/tmp.nOUpMgCzQe/a/managed submodule update --init --recursive
  ok already up to date at 24f2d564
--- after
  $ git status -sb  ->  ## prod-hd...origin/prod-hd
```

### 4. `git diff` on `install.sh`

Round 1 changed the default alone. Round 2 replaced that default with a resolve, which is item 10;
the whole file diff is:

```diff
diff --git a/install.sh b/install.sh
index 40e224b6..2f408a2c 100755
--- a/install.sh
+++ b/install.sh
@@ -5,7 +5,8 @@
 set -euo pipefail
 
 REPO_URL="${KOOMPI_REPO:-https://github.com/koompi/koompi-hd.git}"
-REPO_REF="${KOOMPI_REF:-main}"
+PROD_REF='prod-hd'
+REPO_REF="${KOOMPI_REF:-}"
 DEST="${KOOMPI_DEST:-$HOME/.local/share/koompi-hd}"
 
 if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
@@ -33,6 +34,19 @@ bootstrap_git() {
 
 bootstrap_git
 
+# prod-hd is the release line, main is where it comes from. A mirror that
+# carries only main, or this repo before the branch was ever pushed, must still
+# install rather than die on "Remote branch prod-hd not found".
+if [[ -n "$REPO_REF" ]]; then
+    say "tracking $REPO_REF (KOOMPI_REF)"
+elif git ls-remote --exit-code --heads "$REPO_URL" "$PROD_REF" >/dev/null 2>&1; then
+    REPO_REF="$PROD_REF"
+    say "tracking $PROD_REF, the line KOOMPI releases from"
+else
+    REPO_REF=main
+    say "$REPO_URL has no $PROD_REF branch; tracking main"
+fi
+
 if [[ -d "$DEST/.git" ]]; then
     say "updating $DEST"
     git -C "$DEST" remote set-url origin "$REPO_URL"
```

`KOOMPI_REF` still overrides, and is now honoured verbatim rather than falling back — an explicit ref
that does not exist should fail loudly rather than quietly install something else.

### 5. The workflow diff, and the YAML

Neither workflow filtered by branch: `push:` and `pull_request:` are unfiltered, so every branch,
`prod-hd` included, already runs both. Adding a `branches:` list would have *narrowed* that to two
branches rather than widening coverage, so the change is the note that says so.

```diff
diff --git a/.github/workflows/installer.yml b/.github/workflows/installer.yml
index df51db03..d152a145 100644
--- a/.github/workflows/installer.yml
+++ b/.github/workflows/installer.yml
@@ -5,6 +5,7 @@
 name: Installer
 
 on:
+  # unfiltered by branch on purpose: prod-hd and main alike run this
   push:
     paths:
       - 'setup'
diff --git a/.github/workflows/tests.yml b/.github/workflows/tests.yml
index 63580a28..ed8c994b 100644
--- a/.github/workflows/tests.yml
+++ b/.github/workflows/tests.yml
@@ -18,6 +18,7 @@
 name: Tests
 
 on:
+  # unfiltered on purpose: every branch, prod-hd and main alike, runs the suite
   push:
   pull_request:
   workflow_dispatch: {}
```

```
.github/workflows/tests.yml        parses; triggers: ['push', 'pull_request', 'workflow_dispatch']
.github/workflows/installer.yml    parses; triggers: ['push', 'pull_request', 'workflow_dispatch']
```

### 6. `shellcheck` and `shellcheck -x`

Each file on its own, which is how round 2's SC2034 report was produced — the earlier run passed all
three files in one invocation, where shellcheck reads the sourced `update.sh` as an input and sees
the variables used, so it never fired.

```
$ shellcheck install.sh
rc=0

$ shellcheck sdata/install/update.sh
rc=0

$ shellcheck tests/test_update_prod_branch.sh
rc=0
```

```
$ shellcheck -x install.sh
rc=0

$ shellcheck -x sdata/install/update.sh
rc=0

$ shellcheck -x tests/test_update_prod_branch.sh
rc=0

$ shellcheck -x setup
rc=0
```

Every one rc 0. The test now carries a single file-level `# shellcheck disable=SC2034` with the
reason above it: every bare global in the file is one `./setup` sets and the sourced `update.sh`
reads. The per-line disables it replaces did not cover a compound assignment line
(`DO_DEPS=false; DO_APPS=true; ...`), which is where the four remaining warnings came from.

### 7. `bash tests/run.sh` tail

```
  ok test_wallpaper_config_write.sh
==> test_wallpaper_decode.sh
  ok test_wallpaper_decode.sh
==> test_workspace_help_onscreen.sh
  ok test_workspace_help_onscreen.sh
==> test_workspace_icon_migration.sh
  ok test_workspace_icon_migration.sh
==> test_workspace_wallpaper_wrap.sh
  ok test_workspace_wallpaper_wrap.sh
==> test_zig_build_abort.sh
  ok test_zig_build_abort.sh

101 passed, 3 skipped, 0 failed
skipped: test_globalmenu.sh test_hypridle_logged.sh test_search_bench_parity.sh
```

rc 0. 101 passed where the pre-J51 tree had 100; the three skips are the pre-existing ones.

### 8. The real checkout at `/home/userx/workspace/koompi-desktop`, before and after

Before, at the start of this job:

```
## koompi-sd
 M dots/.config/quickshell/koompi/modules/koompi/sidebarRight/SidebarRightContent.qml
?? dots/.config/quickshell/koompi/modules/koompi/sidebarRight/ChargeLimitRow.qml
```

After both rounds, with every check above run:

```
## koompi-sd
 M dots/.config/quickshell/koompi/modules/koompi/sidebarRight/SidebarRightContent.qml
?? dots/.config/quickshell/koompi/modules/koompi/sidebarRight/ChargeLimitRow.qml
```

`diff` of the two files: identical, no output. Nothing in this job ran against that path except
`git status -sb`, `git count-objects -vH`, `git rev-list --count` and a `git show` of J49's report
blob, all read-only. Every fixture repo was built under `mktemp -d`.

### 9. (addendum) An update runs the code it just pulled

The fixture is a repo whose `setup` is replaced by the commit the update pulls: the checkout holds
v1, `origin/main` holds v2, and one invocation has to end up executing v2.

```
the checkout has setup v1; origin/main now has v2
--- $ ./setup update --no-deps --yes   (one invocation)

==> Updating the checkout
     $ git -C "/home/userx/.tmp/tmp.bsabNNX5tw/machine" pull --ff-only
From /home/userx/.tmp/tmp.bsabNNX5tw/koompi/koompi-hd
   1986ec6..ca58ab7  main       -> origin/main
Updating 1986ec6..ca58ab7
Fast-forward
 setup | 2 +-
 1 file changed, 1 insertion(+), 1 deletion(-)
     $ git -C /home/userx/.tmp/tmp.bsabNNX5tw/machine submodule update --init --recursive
  ok updated 1986ec69 -> ca58ab73
  -> 1 new commit(s)
PULL_MOVED=true
  -> the checkout moved; re-running this update from the tree it just pulled
I am setup v2 from the pulled tree. argv: update --no-deps --yes
KOOMPI_UPDATE_REEXEC=1
--- the same call again, in the second pass
  -> the checkout moved again; continuing with the code already loaded
```

`I am setup v2` is the pulled tree's own `setup`, running inside the invocation that pulled it —
J49's two-consecutive-updates gap closed. The last line is the guard: with `KOOMPI_UPDATE_REEXEC=1`
already in the environment there is no second re-exec, so it cannot loop.

Three details the shape needed:

- **argv.** `run_update` never sees `$@`, so the re-exec rebuilds it from what `parse_install_options`
  set. A test reads the option list straight out of `setup` and fails if one appears there that the
  rebuild would drop (`--only-*` and `--help` are the declared exceptions: `--only-deps` is exactly
  `--no-apps --no-setups --no-files`).
- **the config merge.** `run_update` dumps the defaults the user is running *before* the pull and
  diffs them against the pulled tree. A naive re-exec makes the child dump the pulled tree and diff
  it against itself, migrating nothing. The parent's dump is handed over in
  `KOOMPI_UPDATE_PRE_DEFAULTS` and the child uses it instead of taking its own.
- **when it fires.** On any HEAD move, the branch switch included, not only on a pull: the tree's
  contents changed either way. A dry run never moves HEAD and never re-execs.

`setup` itself is untouched; the argv rebuild is what avoids reaching into a file this round has no
owner for, the same call J49 made.

### 10. (round 2) `install.sh` resolves the ref instead of assuming it

The hazard, run rather than described. `install-before.sh` is this file as round 1 left it, against a
remote that carries only `main` — a mirror, or this repo until `prod-hd` is first pushed:

```
############ a remote that has only main (a mirror, or this repo before prod-hd is pushed)
--- round 1's install.sh (REPO_REF defaulted straight to prod-hd)
==> cloning file:///home/userx/.tmp/tmp.N0e1ik45nd/mirror/koompi/koompi-hd.git (prod-hd)
Cloning into '/home/userx/.tmp/tmp.N0e1ik45nd/d1'...
fatal: Remote branch prod-hd not found in upstream origin
rc=128

--- this round's install.sh
==> file:///home/userx/.tmp/tmp.N0e1ik45nd/mirror/koompi/koompi-hd.git has no prod-hd branch; tracking main
==> cloning file:///home/userx/.tmp/tmp.N0e1ik45nd/mirror/koompi/koompi-hd.git (main)
Cloning into '/home/userx/.tmp/tmp.N0e1ik45nd/d2'...
==> handing over to ./setup install
stub setup ran: install
rc=0  branch: main

############ a remote that has prod-hd
==> tracking prod-hd, the line KOOMPI releases from
==> cloning file:///home/userx/.tmp/tmp.N0e1ik45nd/full/koompi/koompi-hd.git (prod-hd)
Cloning into '/home/userx/.tmp/tmp.N0e1ik45nd/d3'...
==> handing over to ./setup install
stub setup ran: install
rc=0  branch: prod-hd

############ KOOMPI_REF still wins
==> tracking main (KOOMPI_REF)
==> cloning file:///home/userx/.tmp/tmp.N0e1ik45nd/full/koompi/koompi-hd.git (main)
Cloning into '/home/userx/.tmp/tmp.N0e1ik45nd/d4'...
==> handing over to ./setup install
stub setup ran: install
rc=0  branch: main
```

`fatal: Remote branch prod-hd not found in upstream origin`, rc 128, before the clone directory even
exists: the one-liner dies with nothing installed and nothing to retry from. The same remote now
falls back and installs, saying which line it took, and a remote that has `prod-hd` still gets
`prod-hd`.

The probe is `git ls-remote --exit-code --heads "$REPO_URL" prod-hd`, which needs no clone and costs
one round trip on a path that is about to clone anyway. It runs after `bootstrap_git`, because on a
machine with no git there is nothing to probe with yet.

This does mean the branch name is now written in two places, `PROD_REF` in `install.sh` and
`PROD_BRANCH` in `sdata/install/update.sh`. `install.sh` is piped from the internet and cannot source
anything, so there is no third option; both are single assignments at the top of their file.

## Mutation evidence

Each mutation is applied to a throwaway copy of the tree, never to the branch.

```
--- mutation: update_pull stops calling follow_prod_branch
rc=1  FAIL: a managed checkout did not move to prod-hd: 
--- mutation: the move is allowed from any branch, not only main
rc=1  FAIL: a developer's branch was hijacked: 
--- mutation: run_update stops re-running from the pulled tree
rc=1  FAIL: run_update no longer pulls and re-runs: run_update() {
--- mutation: the re-exec guard is removed
rc=1  FAIL: the re-exec guard did not hold:   -> the checkout moved; re-running this update from the tree it just pulled
--- mutation: the rebuilt argv drops --yes
rc=1  FAIL: the re-exec did not carry the options this run was given:   -> the checkout moved; re-running this update from the tree it just pulled
--- mutation: install.sh loses the fallback and demands prod-hd
rc=1  FAIL: install.sh did not say which line it took: ==> cloning file:///home/userx/.tmp/tmp.zz4ij5bBz7/e/koompi/koompi-hd.git (prod-hd)
--- mutation: install.sh never finds prod-hd and always takes main
rc=1  FAIL: install.sh did not clone prod-hd when the remote has it: ==> file:///home/userx/.tmp/tmp.oa6j0vwVN8/e/koompi/koompi-hd.git has no prod-hd branch; tracking main
--- mutation: install.sh ignores KOOMPI_REF
rc=1  FAIL: KOOMPI_REF=main was overridden: ==> tracking prod-hd, the line KOOMPI releases from
```

## What the lead has to do next

1. Merge this.
2. Push `prod-hd`, and tag `v0.1` at the same commit.

The order no longer matters and nothing breaks in between. Before the branch exists a fresh install
takes `main` and says so, and every existing machine keeps updating exactly as it does today, in
silence. After it exists, new installs land on it and managed checkouts move themselves.

## Out of scope, untouched

`prod-hd` and `v0.1` are not created here and nothing pushes. The pacman repo, the ISO,
`setups/system.sh` and the rename were left alone, and no SD-flavour work was done: the branch name
lives in one assignment per file, which is all `prod-sd` will need.

## Commits

```
39172d2a install: resolve prod-hd, fall back to main, say which line it took
75c48f51 work: J51 report — prod-hd follow, the managed-checkout rule, and J49 F1 closed
6309ae27 ci: say why the workflow triggers carry no branch filter
2de70281 update: re-run the installer from the tree the update just pulled
b472091f update: a managed checkout follows prod-hd
3ef2f9e8 install: a fresh install lands on prod-hd, not main
```
