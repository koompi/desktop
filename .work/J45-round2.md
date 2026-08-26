# J45 — round 2 (lead's review of `444d9c9d`, rebased on main)

Fix on your branch, same files; re-run the J45 gates and append a "Round 2" section to `.work/J45-report.md`.

1. `AiChat.qml:171` assigns `onVisibleChanged` on the ModelPicker instance, which replaces the handler inside
   `ModelPicker.qml:72-77`: on open `selectedIndex` is never seeded from `currentId` and `revealRow` never runs, so with the
   current model at row 7 nothing is highlighted, Enter is a no-op and Down jumps to row 0. Seed inside the component (a
   `Connections` on itself, or fold the seeding into `focusFirst()`), and make the probe instantiate the picker the way
   `AiChat.qml` does (with the same instance-level handler) so this cannot regress.
2. Accessibility: rows are `focusPolicy: Qt.NoFocus` and the root has no `Accessible.role`/`name`, so a screen reader hears
   nothing on open or on Up/Down (AttachMenu moves real focus per item). Give the root `Accessible.role: Accessible.List` and a
   name, rows `Accessible.role: Accessible.ListItem` with `Accessible.name` and `Accessible.selected` bound to the highlight.

Accepted as is: dismissal on focus loss while the sidebar closes; a list that grows while the picker is open shifting the
highlight; the duplicate `/model` wiring through two objects.
