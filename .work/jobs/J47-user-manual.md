# J47 — User manual, "Coming from Mac or Windows" first (O19)

`.work/OMARCHY-AUDIT.md` row O19. `README.md:26-28` points a new user at `docs/navigation.md`
(340 lines), which is a specification for us, not a manual for them.
`modules/koompi/tour/steps.js` runs a 15-step in-session tour and then there is nothing to read.
KOOMPI students arrive from Windows, some from macOS.

## Voice

Rithy's, not a manual-voice pastiche. Read `~/.claude/rithy/PERSONA.md` and the VOICE file it
points at, and follow it. Short sentences. Second person. No marketing, no "seamlessly", no
"powerful", no rule-of-three flourishes. One sentence per line in the Markdown (house rule).
This ships as a **draft for Rithy to approve line by line** — say that in your report, do not
claim the voice is settled.

## The hard constraint

Every command, keybind, path, menu item and setting the manual names must exist in this tree,
verified by you, at a `file:line`. A manual that documents a feature we do not ship is worse than
no manual. The runnable check in Do 5 exists to keep it that way.

Sources of truth: `dots/.config/hypr/hyprland/keybinds*.lua` (and the other bind modules) for keys,
`dots/.local/bin/koompi-*` plus `cli/src/main.zig` for commands, `docs/navigation.md` for the
shell's surfaces, `modules/koompi/tour/steps.js` for what the tour already teaches.

## Files you own

- new `docs/manual/*.md` and `docs/manual/README.md` (the index)
- `README.md` — the pointer line at `:26-28` only
- new `tests/test_manual_references.sh`

Do not touch `docs/navigation.md`, `docs/conventions.md`, `docs/agents/**`, or any shell file.

## Do

1. Read the tour steps and `docs/navigation.md` first, then decide the chapter list. **Cap: 12
   chapters, each ≤ 150 lines.** Chapter 01 is "Coming from Mac or Windows": the Super key, where
   the Windows taskbar / macOS dock went, how windows tile, what replaced Finder/Explorer, where
   settings live, how to install software, what closing the lid does.
2. Write the remaining chapters around what a student actually does: launching apps and Search,
   moving between workspaces, windows and tiling, the bar and its indicators, files and USB drives,
   the internet and Wi-Fi, printing and screenshots, the AI sidebar, keeping the machine updated
   (`koompi update`), backups and snapshots, and where to get help. Drop any chapter whose feature
   you cannot verify in the tree; say which you dropped and why.
3. Every keybind you print gets checked against the bind modules. Every `koompi` subcommand gets
   checked against the CLI. Note the `file:line` in your report, not in the manual.
4. `docs/manual/README.md`: the chapter list with one line each, and the "start here" pointer.
   Repoint `README.md:26-28` at it, keeping `docs/navigation.md` where it is for us.
5. `tests/test_manual_references.sh`: extract every `Super+…` chord and every `koompi <subcommand>`
   / `koompi-*` token from `docs/manual/*.md` and fail when one has no match in the bind modules,
   `dots/.local/bin/`, or the CLI's command list. It must fail loudly if someone later adds a
   chapter about a feature we removed — prove that by temporarily adding a fake keybind line,
   showing the red, and removing it.
6. `shellcheck` and `shellcheck -x` clean on the new test.

## Acceptance

Paste real output for each:

1. `wc -l docs/manual/*.md` — 12 chapters or fewer, none over 150 lines.
2. `bash tests/test_manual_references.sh` — all PASS, rc 0.
3. The deliberate-failure demonstration from Do 5: the red run, then the green one after removal.
4. Chapter 01 in full, in your report, so the lead can read the voice without opening the tree.
5. The verification table: every keybind and command the manual names, with the `file:line` that
   proves it exists.
6. `shellcheck tests/test_manual_references.sh && shellcheck -x tests/test_manual_references.sh`
7. `git diff README.md` — one pointer line, nothing else.

## Out of scope

- A docs site, a build step, screenshots, images, translation (Khmer comes later, and it is Rithy's).
- Changing any behaviour to match the manual. If the tree is wrong, report it; do not fix it here.
- The tour, `docs/navigation.md`, agent docs.

## Stop conditions

- A chapter you cannot ground in the tree → drop it and report; never write aspirational docs.
- The manual would need a behaviour change to be true → stop and report it as a finding.
- You find yourself writing more than 12 chapters or a chapter over 150 lines → stop, the scope
  is wrong and that is the lead's call.
