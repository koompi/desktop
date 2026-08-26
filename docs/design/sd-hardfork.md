# Retiring Otto — the hard fork

Rithy's call, 2026-08-26: hard fork Otto at its current commit, stop tracking upstream, and make it KOOMPI's own.
This document is how that is done without breaking the session, and what KOOMPI takes on by doing it.

One thing worth saying once: upstream is small but not dead — roughly 26 commits in three months — and five of the fixes from the [live audit](../../../otto/docs/otto-plan.md) were headed upstream as clean commits. After the fork those are KOOMPI's to carry alone. That is the price of owning the stack, and it is a reasonable one to pay.

## The fork has to cut three upstreams, not one

This is the finding that shapes everything else.
Otto does not merely *use* upstream projects; it depends on two **git branches** in the same maintainer's account:

| dependency | source | locked commit | size |
| --- | --- | --- | --- |
| Otto itself | `nongio/otto` | fork at `koompi/otto`, branch `koompi` | ~92k lines |
| Smithay | `nongio/smithay`, branch `feat/dmabuf-scanout` | `90db50ef` | ~115k lines |
| LayersEngine | `nongio/layers`, branch `feat/subtree-buffer-render` | `3d3ca657` | ~22k lines |

`layers` is pulled by `otto`, `otto-kit` and `otto-auth-ui` — three separate `Cargo.toml` files.

`Cargo.lock` pins the resolved commits, so builds are reproducible *today*.
They stop being reproducible the moment either branch is force-pushed, renamed or deleted and the pinned commit becomes unreachable.
**A fork that leaves those two in place is not a hard fork.**

### What to do with each

**Otto** — fork, restart, rename, own. The rest of this document.

**Smithay** — **fork it.** Decided 2026-08-26.

Rebasing its two patches onto upstream would keep KOOMPI on the real platform, but it means carrying a pinned upstream rev forever — the one pin the hard fork could not delete. Forking to `koompi/smithay` and tagging it removes the last external pin and makes the tree fully self-contained. That was the goal, so that is the answer.

What it costs, stated plainly: no upstream Smithay work arrives for free again. Every new Wayland protocol upstream implements — starting with the two SD is already missing, `wlr-output-management` and `ext-workspace-v1` — is KOOMPI's to write.

Still worth doing once, before the fork closes the door: offer the two patches (dmabuf scanout, XWM focus) upstream as clean commits. It costs an afternoon and it is the polite exit. *Measure the real divergence first* — "two patches" is a Cargo comment, not a verified diff.

**LayersEngine** — 22k lines of Skia scene graph, no upstreaming path since the branch is the author's own working branch. Fork to `koompi/layers` and tag it; once KOOMPI owns the repo there is nothing to pin against.
This is the heaviest inherited liability in the whole stack: it is the rendering engine every pixel goes through, no other project uses it, and nobody at KOOMPI has read it.

## What KOOMPI ends up owning

After the fork, three repositories, all first-party, all tagged, no pins anywhere:

| repo | inherited from | lines |
| --- | --- | --- |
| `koompi/koompi-sd` | `nongio/otto` (MIT) | ~92,000 |
| `koompi/smithay` | `Smithay/smithay` via `nongio/smithay` (MIT) | ~115,000 |
| `koompi/layers` | `nongio/layers` (**no licence** — see below) | ~22,000 |

**~229,000 lines of Rust**, none of it written here, all of it now KOOMPI's to maintain.
That is the real size of the decision and it should be quoted honestly whenever the SD roadmap is discussed.

Whether the three stay separate repositories or get vendored into one Cargo workspace under `koompi/koompi-sd` is an open question — vendoring removes even the git-dependency indirection and leaves a single tag to cut, at the cost of a very large repository. Not decided here.

## Licence

**The SD tree is MIT.** Not chosen — inherited, and it happens to be the most open realistic option.

Otto is MIT, © 2024 Riccardo Canalicchio.
KOOMPI cannot relicense his contribution, so the combined work can only be offered under the common denominator, which is MIT.
"MIT OR Apache-2.0" — the Rust ecosystem default — is **not** available for this tree, because KOOMPI cannot add the Apache option to code it does not own.
It is the right default for new KOOMPI-original repos, where the Apache-2.0 half carries an explicit patent grant that bare MIT lacks.

Rules that follow:

- Keep `LICENSE` naming Canalicchio for the inherited code. Add KOOMPI's copyright **alongside**, never in place of it.
- Renaming binaries and D-Bus names is not a licence question. Dropping the copyright notice is, and it is the one thing here that would actually be wrong.
- `koompi-desktop` stays GPL-3.0 — it derives from end-4 and has no choice. HD and SD therefore sit under different licences, which is fine because they share no code: the Zig daemons speak NDJSON over pipes between separate processes, so nothing links across the boundary.

### The dependency tree is permissive-clean

Scanned `otto/Cargo.lock`: 895 packages, 821 with a resolvable licence field.

| licence | count |
| --- | --- |
| MIT OR Apache-2.0 (all spellings) | 489 |
| MIT | 214 |
| Apache-2.0 | 15 |
| BSD-3-Clause | 11 |
| MPL-2.0 | 9 |
| others (Unicode-3.0, ISC, Zlib, Unlicense) | ~40 |

**No GPL or AGPL anywhere.**
The nine MPL-2.0 crates are file-level weak copyleft and combine with MIT without affecting the rest of the tree.
Nothing in the dependency graph forces SD away from a permissive licence.

### Blocker: LayersEngine has no licence

`nongio/layers` ships **no `LICENSE` file, no `license` field in `Cargo.toml`, and no licence statement in its README**; the GitHub API reports its licence as `null`.
Confirmed against the pinned commit `3d3ca657` and against the repository itself on 2026-08-26.

No licence means no grant. Under default copyright, KOOMPI has no permission to redistribute it — and `koompi-sd` statically links it into every binary it ships.

**This now blocks step 3, not just shipping.** Creating `koompi/layers` publishes a copy of unlicensed code under KOOMPI's own account — redistribution, which is exactly what there is no grant for. The fork of `layers` cannot happen until this is cleared.

In order of preference:

1. **Ask the author to add one.** He maintains both Otto and layers and is reachable on the Matrix channel Otto's README lists. MIT would match Otto and cost him nothing. This is a two-line change upstream and it is almost certainly just an oversight.
2. **Record it honestly until then.** KOOMPI has a precedent: `koompi-kiri` declares `license=('LicenseRef-koompi-kiri-undeclared')` with a comment explaining there is no grant to name. `koompi-sd` should do the same rather than claim MIT.
3. **Replace it.** 22k lines of Skia scene graph, and every pixel goes through it. Last resort.

Do (1) now — before the hard fork removes the reason to talk to upstream at all, and before step 3 needs the answer. Pair it with the Smithay patch offer above: one conversation, both asks.

## History

Reuse the pattern this repo already ran, documented in [`UPSTREAM.md`](../../UPSTREAM.md): `koompi-desktop` restarted from a single root commit and kept the full pre-restart history read-only at `koompi/koompi-desktop-history`.

- `koompi/koompi-sd` — restarted, single root commit, KOOMPI's history from there. Matches the package name.
- `koompi/otto-history` — the current tree with upstream's commits, archived read-only as the authoritative record of what came from where.
- An `UPSTREAM.md` in the new repo, same shape as this one's: fork point, what was inherited, what KOOMPI authored, the licence rule.

## Naming

Rithy, 2026-08-26: the package is **`koompi-sd`**, not `koompi-otto`. Nothing named otto ships.

That settles the hierarchy by mirroring what HD already does:

| role | HD | SD |
| --- | --- | --- |
| edition metapackage | `koompi-desktop-hyprland` | `koompi-desktop-sd` |
| compositor + components | `koompi-hyprland` | `koompi-sd` |
| session launcher | `/usr/bin/koompi-session` | `/usr/bin/koompi-sd-session` |
| session entry | `koompi-hd.desktop` | `koompi-sd.desktop` |
| `XDG_CURRENT_DESKTOP` | `KOOMPI-hd:KOOMPI:Hyprland` | `KOOMPI-sd:KOOMPI` |

The compositor token drops out of SD's desktop string entirely — there is no third-party compositor left to name.

**Binaries take the `koompi-sd-` prefix, not a bare `sd-`.**
`sd` is an existing Arch `extra` package (`sd 1.1.0`, "Intuitive find & replace"), so `/usr/bin/sd` is already claimed and taking it would file-conflict for anyone who has it installed.
So: `koompi-sd` (compositor), `koompi-sd-bar`, `koompi-sd-islands`, `koompi-sd-lock`, `koompi-sd-greeter`, `koompi-sd-rdp`, and `xdg-desktop-portal-koompi-sd`.

D-Bus takes `org.koompi.sd.*` in place of `org.otto.*`, and `org.freedesktop.impl.portal.desktop.koompi-sd` in place of `…desktop.otto`.

## The rename

203 tracked files carry `otto` in their path; `otto` appears 3,349 times in tracked text.
Most of that is cosmetic. The following are not — each is a wire-visible or on-disk contract:

| surface | current | what breaks if it moves alone |
| --- | --- | --- |
| Portal D-Bus name | `org.freedesktop.impl.portal.desktop.otto` | xdg-desktop-portal's backend lookup. The `.portal` file, the `.service` file and the systemd unit must move in the same commit |
| D-Bus interfaces | `org.otto.Settings`, `.Compositor`, `.ScreenCast` (+`.Session`, `.Stream`, `.ListWindows`), `.Island`, `.Dialog`, `.music` | every component that calls them |
| Wayland protocols | `otto-dock-v1`, `otto-surface-style-unstable-v1`, `sc-layer-v1` | interface names travel on the wire; any client built against the old XML |
| Config paths | `~/.config/otto`, `/etc/otto/config.toml` | every existing install — needs a migration |
| PAM | `/etc/pam.d/otto-lock` | lock screen and greeter authentication |
| Binaries | `otto`, `otto-bar`, `otto-islands`, `otto-lock`, `otto-greeter`, `otto-rdp` | `exec_once`, the session entry, packaging |
| Package | lands as `koompi-sd` in step 1, with `provides`/`conflicts` `otto` until the binaries move | pacman |

Do the rename as **one mechanical commit against that checklist**, not as a sweep of 3,349 strings.
And do it only once a smoke test exists, because the audit already proved that the portal chain is where this stack breaks silently: a wrong backend name does not error, it falls through to GTK and the desktop comes up light.

The package name is the exception and moves first: it is a `pkgname` field plus `provides`/`conflicts`, costs nothing, and means no `koompi-otto` ever exists in this repo's history.

## No more pinning

Pinning a commit and bumping it by hand is upstream-tracking machinery.
The hard fork removes the upstream, so it removes the machinery: **`koompi-sd` is a first-party package and versions off a tag in `koompi/koompi-sd`, like `koompi-session` and `koompi-shell` do.**

- No `_commit` variable, no 40-char SHA in the PKGBUILD, no "bump after rebase" step in any document.
- No `pkgver()` either — `sdata/dist-arch/README.md` already forbids it, because makepkg rewrites the tracked PKGBUILD.
- `pkgver` is the release; cutting a release means tagging the repo and bumping one field, which is what every other KOOMPI-original package already does.
- The `koompi` branch stops being "rebasable onto upstream". It becomes `main`.

The one place a pin could survive is upstream Smithay, if KOOMPI rebases onto it rather than forking it. That is the argument for forking it, made above.

`otto/docs/otto-plan.md` carried the old instruction — "bump `_commit` … after each `git rebase upstream/main`" — and has been marked superseded in place.

## Order of operations

1. ~~**Land the packaging as `koompi-sd`.**~~ **Done 2026-08-26.** `sdata/dist-arch/koompi-sd/PKGBUILD`, sourcing the tag `koompi-sd-0.16.0`, no `_commit`, no `pkgver()`. Declares `LicenseRef-koompi-sd-undeclared` for the reason in [Licence](#licence), and `provides`/`conflicts`/`replaces` the otto names until step 5 renames the binaries.
   The tag is cut on `koompi/otto` locally and **not yet pushed**; until it is, `makepkg` cannot fetch it: `git -C ~/workspace/otto push origin koompi-sd-0.16.0`.
2. **Session smoke test** in `tests/` — next: portal colour scheme, bar count against output count, SNI count, and that `otto-bar`, `otto-islands` and the polkit agent are alive. This is what makes step 5 safe, and the audit notes it would have caught three of its four blockers.
3. **Cut the dependency forks.** `koompi/smithay` and `koompi/layers`, both tagged. Repoint every `Cargo.toml` off the `nongio` branches — three files reference `layers`, two reference `smithay`. After this, no build depends on an account KOOMPI does not control. **Gated on the `layers` licence being resolved**, since this step publishes a copy of it.
4. **Restart the repo.** `koompi/koompi-sd`, single root commit, `koompi/otto-history` archived, `UPSTREAM.md` written.
5. **Rename**, one commit, against the checklist above, smoke test green before and after.
6. **Migration** for existing installs: `~/.config/otto` to the new path. `koompi-migrate new <slug>` writes the skeleton; [`docs/agents/migrations.md`](../agents/migrations.md) is the rule.

Steps 1 and 2 are worth doing whether or not the fork happens, and step 1 is already blocking.
Step 3 is the one that actually constitutes the hard fork; the rename in step 5 is what makes it visible, but step 3 is what makes it true.

## What KOOMPI takes on

- The eleven findings from the live audit, with no upstream to send any of them to.
- A 22k-line Skia scene-graph renderer that nobody here has read and no other project uses.
- Smithay tracking, directly. Better than tracking it through two forks, and now KOOMPI's job.
- Every future Wayland protocol, including the two SD is already missing — `wlr-output-management` and `ext-workspace-v1`.

## Open decisions

1. ~~The compositor's name.~~ **Answered: `koompi-sd`.** See [Naming](#naming).
2. ~~Smithay: rebase or fork?~~ **Answered: fork.** `koompi/smithay`, tagged, no pin. Offer the two patches upstream on the way out.
3. **Rename the Wayland protocol interfaces, or keep them?** Renaming is cleaner. Keeping is cheaper, and no third-party clients exist yet — so this is reversible for exactly as long as that stays true.
4. ~~Relicense the tree GPL-3.0, or keep MIT?~~ **Answered: MIT.** The inherited MIT code cannot be relicensed by KOOMPI, and MIT is the most open option available. New KOOMPI-original repos should use MIT OR Apache-2.0 for the patent grant.
