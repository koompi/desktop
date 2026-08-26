# J51 — `koompi update` follows the newest release tag, not `main`

Rithy, 2026-08-26: after v0.1 exists, an existing user's `koompi update` should move to the newest
release tag rather than to whatever `main` is at that moment. KOOMPI ships to school laptops; they
should only ever land on points that have been blessed.

**Serial after J50** (same file: `dots/.local/share/koompi/libexec/update`). Do not start until the
lead says J50 is merged.

## Where it lives

`update_pull` (`sdata/install/update.sh:10-70`) is the whole of today's behaviour: it refuses when the
checkout is not a git tree, refuses on detached HEAD (`:20-23`), refuses when the tree is dirty
(`:25-29`), then `git pull --ff-only` on the current branch with a retry/skip/abort prompt.

The git route reaches it through `"$repo/setup" update` → `run_update` (`sdata/install/update.sh:117`),
from both `update_from_git` (`libexec/update:598`) and the packaged route's fallback (`:571-583`).

## The care this job is really about

Not hijacking a checkout someone works in. The lead's own tree is `main` with local commits and
uncommitted work; a developer's clone must be left exactly where it is, and must not end up detached.
The existing detached-HEAD refusal has to become "detached at a release tag is fine, detached anywhere
else is still hands-off".

## Files you own

- `sdata/install/update.sh`
- `dots/.local/share/koompi/libexec/update` (only if the route genuinely needs it; prefer not to)
- new `tests/test_update_release_tag.sh`
- `docs/agents/` — one short page or section if the behaviour needs documenting

## Do

1. Fetch tags before deciding anything (`git fetch --tags --prune`), and pick the newest `v*` tag by
   version order, not by date or by string sort.
2. Move the checkout to that tag only when **both** hold:
   - the working tree is clean (today's `:25-29` guard, kept), and
   - HEAD is either detached at some `v*` tag, or on a branch that carries nothing of its own
     (`git merge-base --is-ancestor HEAD @{u}`, i.e. no local commits, and an upstream exists).
   Anything else: leave the checkout alone, do what today does, and say in one line why.
3. No `v*` tag exists → today's behaviour exactly. This must hold, because it is the state of every
   machine until v0.1 is published.
4. An explicit opt-out puts a user back on `main` and keeps them there — an env var or a flag, whichever
   fits the file's existing style. Document it where a user will find it.
5. Report the move the way `update_pull` already reports a pull: what it moved from, what to, and how
   many commits, so `koompi doctor --last-update` still reads sensibly.
6. `tests/test_update_release_tag.sh`: build a fixture repo in a temp dir with `git init`, a couple of
   commits and two `v*` tags, and drive the function over it. Never touch the real remote, never the
   real checkout. Cover: picks the newest tag and not the alphabetically-last one; no tags means the
   old path; a dirty tree is left alone; a branch with a local commit is left alone; a checkout already
   detached at the newest tag is a no-op; the opt-out returns to `main`.
7. `shellcheck` and `shellcheck -x` clean.

## Acceptance

Paste real output for each:

1. `bash tests/test_update_release_tag.sh` — every PASS, rc 0.
2. The fixture transcript for the "developer checkout" case, showing it was left untouched.
3. The version-order proof: tags that would sort wrongly as strings (`v0.2` vs `v0.10`) pick correctly.
4. `bash tests/test_update_route.sh` and `bash tests/test_migrate*.sh` (whatever exercises this path)
   still pass.
5. `shellcheck` + `shellcheck -x` on both files you touched.
6. `bash tests/run.sh` tail.
7. `git -C /home/userx/workspace/koompi-desktop status -sb` before and after your test run, proving
   the real checkout never moved.

## Out of scope

- Creating the v0.1 tag or the GitHub release. The lead does that after you land.
- The pacman repo, the rename, `setups/system.sh`.
- Changing what an install does. Only the update path.

## Stop conditions

- **Nothing you run may move, detach or dirty the real checkout at
  `/home/userx/workspace/koompi-desktop`.** Fixtures in a temp dir only.
- The clean rule set above would still detach a developer's tree in some case you can construct →
  stop and report the case; the rule is the deliverable, not the code.
- You need `libexec/update` restructured to make this fit → stop and report; that file is on the
  length allow-list and J50 has just moved through it.
