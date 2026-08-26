# J45 — round 3 (last; lead's review of the round-2 branch, now `c6257495` on main)

1. `ModelPicker.qml:83` schedules `revealRow` with `Qt.callLater`, which runs before the Flickable/ColumnLayout geometry is
   polished on the first open: `row.y`, `row.height`, `list.height` are still 0, so `contentY` is left alone and a current
   model near the bottom of a 10+ row list opens off-screen until the first arrow key. Re-run the reveal once geometry exists
   (e.g. from the list's `contentHeightChanged`/`heightChanged` while visible, or a reveal that retries when the sizes are 0).
   Probe: 12 fake models with the current one last → after open, the current row is inside the viewport.
2. `ModelPicker.qml:233-236` sets the highlight from hover on `containsMouse`; arrow keys scroll the list under a resting pointer
   and the hover snaps the selection back. Select from hover only on actual pointer movement (`onPositionChanged`, or ignore
   hover while the last input was a key).

Re-run the J45 gates, append "Round 3" to the report, commit, say DONE. Same rules as before.
