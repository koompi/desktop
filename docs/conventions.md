# Naming conventions

One convention per kind of name, and one list of what does not follow it.
Where this document and the code disagree, the code is the defect, except for the exceptions listed at the bottom.

This governs `dots/.config/quickshell/koompi`, the Quickshell shell.
`dots/.config/hypr` is Lua and keeps Lua conventions; see the exceptions.

## Files and directories

| Kind | Convention | Example |
| --- | --- | --- |
| QML component | PascalCase, one component per file, filename is the type name | `SearchPanel.qml`, `StyledText.qml` |
| QML singleton | PascalCase, same rule | `modules/common/Appearance.qml`, `services/HyprlandXkb.qml` |
| Directory | lowerCamelCase | `modules/koompi/sidebarRight`, `modules/koompi/wallpaperSelector` |
| Shell script | kebab-case | `recognize-music.sh`, `manage-translations.sh` |
| Python module | snake_case, because it has to be importable | `scheme_for_image.py`, `token_from_key.py` |
| JavaScript helper | kebab-case, chosen for new files to match scripts and assets; only one existing file follows it | `window-layout.js` |
| SVG asset | kebab-case, `-symbolic` suffix if it is recoloured by the theme | `cloudflare-dns-symbolic.svg`, `add-filled.svg` |
| Translation file | the locale code exactly as `Qt.locale().name` produces it | `km_KH.json`, `zh_CN.json` |

A QML file whose name is not a valid type name cannot be instantiated as a component.
That is why the entry points are the shape they are; see exception 1.

## File and function length

| Kind | File cap | Function cap |
| --- | --- | --- |
| QML | 400 | 60 |
| JavaScript, Lua | 300 | 50 |
| bash: `*.sh`, `setup`, `install.sh`, everything in `dots/.local/bin/` | 400 | 60 |
| Zig | 600 | 80 |
| Rust | 600 | 80 |

`dots/.local/share/koompi/libexec/*` is bash without an extension and takes the bash caps.

A file is read whole: someone opening it to change one thing has to hold all of it to know what that change touches, and past a few hundred lines nobody does.
A function should fit on one screen, so its control flow can be seen without scrolling and its locals can be counted.
When a file is over the cap it is doing more than one thing, and the fix is to split it by concern, not to trim comments.
Data that happens to be in a source file (a defaults schema, an emoji table) belongs in a data file, where no length rule applies.

The file cap is enforced by `tests/test_file_length.sh` as a ratchet.
Files that were over the cap on the day the rule landed are listed in `tests/file-length-allow.txt` with their line count at the time.
A listed file may only shrink: the test fails if it grows past its listed count, and the row is removed once it is under the cap.
A new file over the cap fails outright.
The function cap is not yet checked by a test; it is the bar for review.

The numbers come from published limits rather than taste:
ESLint `max-lines` defaults to 300 lines per file and `max-lines-per-function` to 50 (<https://eslint.org/docs/latest/rules/max-lines>);
the Linux kernel coding style says a function should fit one or two screenfuls, about 48 lines, and do one thing (<https://www.kernel.org/doc/html/latest/process/coding-style.html>);
the Google Shell Style Guide says a script over about 100 lines with non-trivial control flow belongs in a structured language, which we keep bash for `setup` in spite of, so 400 is the warning line for a single file;
SonarQube's "files should not have too many lines" defaults to 1000, the ceiling nobody should reach.
QML, Zig and Rust get more room than JavaScript because their declarations are longer per unit of behaviour.

## Identifiers inside QML

Everything is lowerCamelCase: properties, functions, `id` values, signals, signal handler arguments.
There are 2366 declared properties in the shell and, after the exceptions below, all of them follow this.

Two prefix rules apply on top of that, and only inside `modules/common/Appearance.qml`:

- `m3` prefixes a raw Material You token as the palette pipeline emits it: `m3surfaceContainerHigh`, `m3onPrimary`.
  These are inputs. Surface code should not read them directly.
- `col` prefixes a resolved shell colour, which is what surface code is meant to bind to: `colLayer1`, `colOnLayer0`, `colSubtext`.
  There are 222 of these.
- `term0` through `term15` are the terminal palette, and are passed through to terminal config rather than used by the shell.

A component that owns a colour local to itself, rather than a shared token, does not take the `col` prefix; see exception 3.

A leading underscore marks a member as private to its own file.
This is used in the long-lived service singletons where the public surface needs to stay small: `_retryAfterCancel`, `_applyCompaction`.
A double underscore means the same thing and carries no extra meaning; prefer one.

## Exceptions

These are known, and they stay until someone has a reason beyond tidiness.

1. **Quickshell entry points are lowercase**: `shell.qml`, `settings.qml`, `welcome.qml`.
   They are addressed as paths by `qs -p`, from `keybinds.lua` and from `FirstRunExperience.qml`, never instantiated as components, and the Quickshell convention for those is lowercase.
   `killDialog.qml` is the same kind of file but camelCase rather than lowercase, so it matches neither rule.
   Its one call site is `services/ConflictKiller.qml:12`, which builds the path from a string literal, so a rename has to move both in the same commit.

2. **Waffle carries a second token vocabulary.**
   `modules/waffle/looks/Looks.qml` defines `bg0`, `bg1`, `bg2`, `accent`, `accentHover` where the rest of the shell would say `colLayer0`, `colLayer1`, `colPrimary`.
   Waffle is a deliberate alternative panel family, 142 QML files against the koompi family's 211, switched at runtime through `panelFamilies/PanelLoader.qml`.
   Its tokens are separate on purpose: it is imitating a different product and should not inherit this one's palette names.
   It is an exception to the prefix rule, not to the lowerCamelCase rule.

3. **Local colour properties are not `col`-prefixed**: `activeColor` and `activeBorderColor` in `StyledSwitch.qml` and `StyledRadioButton.qml`, `bg0`-style names in `OverviewWidget.qml`.
   These are per-component knobs, not shared tokens, and the `col` prefix is reserved for `Appearance`.

4. **Shell script names are split three ways.**
   16 are kebab-case, 5 are snake_case (`apply_wall.sh`, `is_unlocked.sh`, `random_wall.sh`, `random_library_wall.sh`, `try_lookup.sh`), 4 are single words.
   The kebab-case group is the majority and the convention above; the snake_case group is inherited and is called from `keybinds.lua` and from other scripts, so renaming is a cross-file change.

5. **Two Python files are kebab-case**: `translation-manager.py` and `translation-cleaner.py`.
   They are CLI entry points that are never imported, so the importability argument does not bind them, but they are still the odd two out of fourteen.

6. **Four JavaScript helpers are neither kebab nor snake**: `fuzzysort.js`, `layouts.js`, `levendist.js`, `paging.js` are single words; `calendar_layout.js` and `periodic_table.js` are snake_case.
   `fuzzysort.js` is vendored third-party code and should keep its upstream name.

7. **`scripts/global-menu/` is the only kebab-case directory** in a tree of lowerCamelCase ones. It holds a Zig project, which has its own build layout.

8. **Three snake_case identifiers mirror an external wire format**: `api_format` and `requires_key` in `services/ai/AiModel.qml`, and `classify_step` in `services/Ai.qml`.
   The first two are keys in the model JSON as the provider defines it, so renaming them would mean translating at the boundary. These should stay snake_case as long as they are read straight off the wire.

9. **`dots/.config/hypr` is Lua and uses snake_case throughout**, files and identifiers alike: `create_custom_config.lua`, `kb_layout`, `numlock_by_default`.
   Much of that is Hyprland's own key vocabulary and is not ours to rename.
