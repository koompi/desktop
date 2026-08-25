# J26 report — length walk covers Rust and `libexec/update`

Branch `j26-length-walk-rust-update` on top of `7ffb7128`.
Files touched: `tests/test_file_length.sh`, `tests/file-length-allow.txt` (rows added only), `docs/conventions.md`. Nothing else.

## Do

1. `cap_for`: `*.rs` → 600 (shares the Zig arm), `dots/.local/share/koompi/libexec/*` → 400 (bash, no extension). Skip list unchanged: `git ls-files | grep -E '(^|/)target/'` returns nothing, so no `target/` arm was added. The existing `*/tests/*` skip already drops `shell-services/*/tests/*.rs` (six files, all under 500 lines); `examples/demo.rs` are counted, all under cap. Header comment updated to name the new kinds.
2. Allow-list regenerated for the new kinds with `awk 'END{print NR}'`, `LC_ALL=C sort` into the existing file. 33 → 38 rows. The five new rows are pasted under Acceptance 1.
3. `docs/conventions.md`: `| Rust | 600 | 80 |` row after Zig; one sentence after the table: "`dots/.local/share/koompi/libexec/*` is bash without an extension and takes the bash caps."; the closing sentence of the sources paragraph now reads "QML, Zig and Rust get more room...".
4. Gate below.

## Stop condition check

No tracked `.rs` is vendored: `git ls-files | grep -iE 'vendor|third[_-]?party'` is empty, every `path =` in a `Cargo.toml` points at a workspace member (`core`, `service`, `hyprland`, ...), and no `.rs` header carries a foreign copyright or "copied from". All 98 tracked `.rs` files are under `shell-services/` or `globalmenu/`.

## Acceptance

### 1. New allow-list rows

```
dots/.local/share/koompi/libexec/update	695
shell-services/mpris/src/service.rs	898
shell-services/network/src/service.rs	1198
shell-services/tray/src/service.rs	682
shell-services/tray/src/watcher.rs	683
```

`tray/src/service.rs` at 682 is the "whatever else over cap" the contract anticipated; nothing else in `git ls-files '*.rs'` is over 600 (next largest: `session/src/service.rs` 521, `globalmenu/core/src/registrar.rs` 507).

### 2. `FILE_LENGTH_ROOT` / `FILE_LENGTH_FILES` demonstration

Scratch dir from `mktemp -d`, removed afterwards; repo untouched.

```
$ awk 'END{print NR}' x.rs -> 601
$ FILE_LENGTH_ROOT="$d" FILE_LENGTH_FILES="$d/list.txt" bash tests/test_file_length.sh; echo "rc=$?"
FAIL: x.rs is 601 lines, cap is 600; split it by concern (docs/conventions.md, File and function length)
rc=1
$ awk 'END{print NR}' x.rs -> 600
$ FILE_LENGTH_ROOT="$d" FILE_LENGTH_FILES="$d/list.txt" bash tests/test_file_length.sh; echo "rc=$?"
ok: 1 files under cap, 0 allow-listed and not grown
rc=0
$ awk 'END{print NR}' libexec/y -> 401
$ FILE_LENGTH_ROOT="$d" FILE_LENGTH_FILES="$d/list.txt" bash tests/test_file_length.sh; echo "rc=$?"
FAIL: dots/.local/share/koompi/libexec/y is 401 lines, cap is 400; split it by concern (docs/conventions.md, File and function length)
rc=1
$ rm -rf "$d"; git status --short
 M docs/conventions.md
 M tests/file-length-allow.txt
 M tests/test_file_length.sh
```

### 3. `./tests/run.sh` tail

```
==> test_zig_build_abort.sh
  ok test_zig_build_abort.sh

79 passed, 3 skipped, 0 failed
skipped: test_globalmenu.sh test_hypridle_logged.sh test_search_bench_parity.sh
```

Unchanged from the main baseline (79 / 3 / 0).

## Gate

- `bash tests/test_file_length.sh`: `ok: 872 files under cap, 38 allow-listed and not grown` (was 778 / 33 before the walk grew; +92 Rust files and `libexec/update` measured, +5 listed).
- `shellcheck tests/test_file_length.sh`: clean.
- `./tests/run.sh`: 79 passed, 3 skipped, 0 failed (above).
- `tests/test_file_length.sh` is 92 lines, under its own cap.

## Commits

- b1c9dd97 test(length): walk Rust (cap 600) and libexec/update (cap 400)
- 8126b0eb docs(conventions): Rust row in the length caps table, libexec counts as bash
