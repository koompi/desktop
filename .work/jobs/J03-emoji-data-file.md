# J03 — move the emoji table out of fuzzel-emoji.sh

## Files you own
- `dots/.config/hypr/hyprland/scripts/fuzzel-emoji.sh`
- `dots/.config/hypr/hyprland/scripts/fuzzel-emoji.txt` (new)

## Do
1. (D2) Move every line after `### DATA ###` (line 28 onward) verbatim into `fuzzel-emoji.txt`, same directory. Byte-identical: verify with `diff <(sed '1,/^### DATA ###$/d' old) fuzzel-emoji.txt`.
2. (D2) Change line 9 to read the data from `"$(dirname "$0")/fuzzel-emoji.txt"` instead of `$0`. Remove the `### DATA ###` marker, the comment at lines 2-3 explaining the trick, and the `shellcheck disable=SC2317,SC1089` line.
3. Confirm the installer records the new file: check how `sdata/install/files.sh` copies `dots/` (it copies the tree, so a sibling file needs no registration; state which lines prove that).
4. `shellcheck fuzzel-emoji.sh` clean.

## Acceptance
1. `wc -l` of both files (script expected ≤ 30, data ≈ 1928).
2. The `diff` from step 1 with empty output.
3. `shellcheck` output (empty).
4. Run `bash -n` and, in a session, `fuzzel-emoji.sh copy` once with `fuzzel` present, or if headless, paste the `sed`-fed candidate count: `sed -n '$=' fuzzel-emoji.txt`.

## Out of scope
- Editing the emoji list contents.
- Any other script in `hyprland/scripts/`.

## Stop conditions
- If the keybind in `dots/.config/hypr/hyprland/keybinds.lua:116` needs changing (it should not; the path is the same), stop and report instead of editing a file you do not own.
