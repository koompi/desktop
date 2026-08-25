# J05 — split sdata/install/setups.sh by concern

## Files you own
- `sdata/install/setups.sh`
- `sdata/install/setups/**` (new directory)

## Do
1. (D5) Read `setups.sh` fully and `sdata/lib/common.sh` for the helpers it uses (`run`, `warn`, `have`, `step`, `info`, `ok`, `manifest_add`, `try`, `sudo_write`, `cargo_usable`, `zig_usable`, `err`, `run_in_dir`, `confirm`). Read `setup:19-30` and `setup:230-240`, `sdata/install/update.sh:70-80` to see who calls what.
2. (D5) Create `sdata/install/setups/` with: `_guards.sh` (`systemd_running`, `systemd_user_running`), `cli.sh` (`setup_koompi_cli`), `globalmenu.sh` (`setup_global_menu`, `setup_globalmenu_rs`), `python.sh` (`setup_python_venv`), `system.sh` (`setup_groups_and_modules`, `setup_suspend_hook`, `setup_services`, `setup_shell_services`), `ai.sh` (`setup_local_ai`, `write_litert_lm_config`, `setup_local_search`), `agent_memory.sh` (`memd_source`, `setup_agent_memory`, `verify_agent_memory`), `desktop.sh` (`setup_portals`, `setup_cursor_default`, `setup_toolkit_defaults`), `session.sh` (`setup_system_session`). Function bodies move verbatim.
3. (D5) `setups.sh` becomes: header comment, `source` of each file relative to its own directory (same idiom `setup:19-27` uses for `REPO_ROOT`), and `run_setups` unchanged. Entry points that must keep their names: `run_setups`, `setup_global_menu`, `setup_services`.
4. Every new file gets the same `# shellcheck shell=bash` header the sourced libs use (see `sdata/lib/common.sh:1-5`), and `shellcheck -x -s bash sdata/install/setups.sh sdata/install/setups/*.sh` is clean.
5. `./setup install --dry-run --no-apps` end to end; paste the Setups step output.

## Acceptance
1. `wc -l sdata/install/setups.sh sdata/install/setups/*.sh` (setups.sh ≤ 40; no file over 200).
2. `grep -c '^[a-z_]*()' ` across the new files summing to 21, and `diff <(grep -o '^[a-z_]*()' old_setups.sh | sort) <(cat setups/*.sh | grep -o '^[a-z_]*()' | sort)` empty.
3. shellcheck output (empty) for the command in step 4.
4. `./setup install --dry-run --no-apps` output for the Setups step, showing every `would run` line the baseline shows (capture baseline first from `main`, then diff the two outputs: expect identical).
5. `./tests/run.sh` tail, unchanged count.

## Out of scope
- `sdata/install/files.sh` (344 lines, the other outlier) — separate job later.
- Changing what any setup step does.

## Stop conditions
- If a function relies on a variable set in `setup` (not in `common.sh`), name it and confirm it is still visible after sourcing from a subdirectory before moving on; if the answer requires editing `setup`, stop and report.
- No sudo, no non-dry-run install.
