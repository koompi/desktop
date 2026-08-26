# J51 — `koompi update` follows `prod-hd`, not `main`

Rithy, 2026-08-26: "for koompi-hd release we should put it in prod-hd branch."

KOOMPI ships to school laptops; they should only land on points that have been blessed, not on
whatever `main` is at that moment. The repo is also about to carry two flavours — HD (Hyprland,
tiling) and SD (Otto/Smithay, stacking), see `docs/design/koompi-sd.md` — so the stable line is
named per flavour: `prod-hd` now, `prod-sd` later.

**The rule that keeps this simple: `prod-hd` only ever fast-forwards from `main`. No commit is ever
authored on it.** A hotfix lands on main and prod-hd moves up to it, so prod-hd's history is always a
prefix of main's and there is never a back-merge. Encode that assumption; do not build for divergence.

A `v0.1` tag will sit at the same commit as prod-hd's first position. The branch answers "what should
this machine be running", the tag answers "what is it running". The lead creates both after you land.

## Where it lives

`update_pull` (`sdata/install/update.sh:10-70`) is today's behaviour: refuses when not a git tree,
refuses on detached HEAD (`:20-23`), refuses on a dirty tree (`:25-29`), then `git pull --ff-only` on
the current branch with a retry/skip/abort prompt. The route reaches it through `"$repo/setup" update`
→ `run_update` (`:117`), from both `update_from_git` (`libexec/update:604`) and the packaged route's
fallback (`libexec/update:575-589`).

Because prod-hd is a branch, `pull --ff-only` still does the work and the detached-HEAD refusal stays
exactly as it is. What is new is only: which branch a managed checkout should be on, and moving it
there once.

## The care this job is really about

Not hijacking a checkout someone works in. The lead's own tree is a dev checkout with its own
branches and uncommitted work; it must be left precisely where it is.

## Files you own

- `sdata/install/update.sh`
- `install.sh` (the `REPO_REF` default only)
- `dots/.local/share/koompi/libexec/update` (only if the route genuinely needs it; prefer not to)
- `.github/workflows/tests.yml` and `installer.yml` (add `prod-hd` to the branch triggers)
- new `tests/test_update_prod_branch.sh`
- `docs/agents/` — a short section where a user or an agent will find it

## Do

1. Decide what makes a checkout *managed*: it is the one this machine updates from, and it carries
   nothing of its own. Move it to `prod-hd` only when all of these hold — the tree is clean, an
   `origin` remote exists that is the KOOMPI repo, `origin/prod-hd` exists, and HEAD carries no
   commits that are not on its upstream (`git merge-base --is-ancestor HEAD @{u}`). Anything else:
   leave it alone, do what today does, and say in one line why.
2. Do the move with `git checkout prod-hd` (creating the tracking branch if needed), then let the
   existing `update_pull` do the `--ff-only` pull. Do not detach, do not reset, do not stash.
3. `origin/prod-hd` does not exist → today's behaviour exactly, silently. This is the state of every
   machine until the lead pushes the branch, and it must not print an error at those users.
4. An explicit opt-out keeps a user on `main` across updates — an env var or a flag, whichever fits
   the file's style. Someone who tracks main deliberately must not be moved back on every run.
5. `install.sh`: `REPO_REF` default `main` → `prod-hd`, so a fresh install lands on the stable line.
   Keep `KOOMPI_REF` as the override.
6. Add `prod-hd` to the push/PR branch triggers in both workflows, so the stable branch is tested and
   not just assumed good.
7. `tests/test_update_prod_branch.sh`: build fixture repos in a temp dir with `git init` — an origin
   with `main` and `prod-hd`, and clones in each state. Cover: a managed checkout on main moves to
   prod-hd and pulls; a checkout with a local commit is untouched; a dirty tree is untouched; no
   `origin/prod-hd` means the old path with no error; a checkout already on prod-hd just pulls; the
   opt-out keeps main. Never touch the real remote or the real checkout.
8. `shellcheck` and `shellcheck -x` clean.

## Acceptance

Paste real output for each:

1. `bash tests/test_update_prod_branch.sh` — every PASS, rc 0.
2. The fixture transcript for the developer-checkout case, showing it was left where it was.
3. The no-`prod-hd`-yet case, showing an ordinary update and no error text.
4. `git diff` on `install.sh` — the `REPO_REF` default and nothing else.
5. The workflow diff, and confirmation the YAML still parses.
6. `shellcheck` + `shellcheck -x` on every file you touched.
7. `bash tests/run.sh` tail.
8. `git -C /home/userx/workspace/koompi-desktop status -sb` before and after your run, identical.

## Out of scope

- Creating `prod-hd` or the `v0.1` tag, and anything that pushes. The lead does that after you land.
- The pacman repo, the ISO, `setups/system.sh` (J49's), the rename (J50, merged).
- Any SD-flavour work. `prod-sd` is a name in a design doc, not a thing to build here.

## Stop conditions

- **Nothing you run may move, detach, dirty or switch the branch of the real checkout at
  `/home/userx/workspace/koompi-desktop`.** It currently sits on a branch of Rithy's with uncommitted
  work. Fixtures in a temp dir only.
- Your rule set would still move a developer's tree in some case you can construct → stop and report
  the case. The rule is the deliverable; the code is downstream of it.
- Making this fit needs `libexec/update` restructured → stop and report. That file is on the length
  allow-list and J50 has just moved through it.
