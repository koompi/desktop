# J38 — Factory reset from `@baseline` (O16) — blocked-on-user

`.work/OMARCHY-AUDIT.md` row O16. `installer/src/post_install.sh:65-81` pins `@baseline` (never pruned, "factory reset point");
`dots/.local/bin/koompi-snapshot` (112) exposes create/list/rollback only. Omarchy's `bin/omarchy-system-factory-reset` returns the
machine to *provisioning* state: root swapped for a clone of the factory snapshot, staged for next boot, LUKS re-keyed to a
throwaway passphrase, `/home` gone.

## The decision (Rithy)
What "factory reset" means for a KOOMPI laptop handed from one student to the next:
- (a) Root only: `snapper -c root rollback <baseline>` + reboot; `/home` untouched. Cheap, reversible, but the previous
  student's files remain.
- (b) Root + home: (a) plus delete every non-system user (`userdel -r`) after a typed confirmation, then reboot into the
  first-boot user creation (`koompi-useradd` / OEM flow — verify it re-arms). Recommended: this is the handover case.
- (c) Omarchy-style re-provision with LUKS re-key. Only if KOOMPI OS installs encrypted by default (`installer/src/config.zig`
  says); otherwise not applicable.

## Files you would own
- new `dots/.local/bin/koompi-factory-reset` (+ `_tools` row), `dots/.local/bin/koompi-snapshot` (a `baseline` lookup),
  `modules/koompi/sessionScreen/` no (out: the session menu is not where a reset belongs), Search row via J34/O05 later,
  new `tests/test_factory_reset.sh` (shims only; the tool is never run for real on any lead or worker machine).

## Stop conditions
- Do not start until Rithy picks (a)/(b)/(c). The worker must never execute the tool outside the shim test.
