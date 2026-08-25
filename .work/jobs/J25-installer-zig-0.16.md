# J25 — port `installer/src` to zig 0.16's std (std.Io)

From J06 (`.work/J06-report.md`, "Addendum 2"): `installer/build.zig` now parses under 0.16's build runner, but
`installer/src/` compiles only against the 0.14 std. The machine, CI (`tests.yml` installs Arch's `zig`, 0.16.0)
and every future contributor have 0.16; the installer is therefore unbuildable everywhere except a hand-fetched
0.14.1. J06 sized the port at 110-140 changed lines across five files and listed the call sites; that list is
your map.

## Files you own
- `installer/src/**`
- `installer/build.zig.zon` (`minimum_zig_version` only)
- `.work/J25-report.md`

## Do
1. Reproduce: `/usr/bin/zig version` (0.16.0), `cd installer && zig build` — paste the first error
   (`src/main.zig: std.heap.GeneralPurposeAllocator`).
2. Port, one file per commit, in this order so each commit builds further than the last: `main.zig` (allocator,
   `std.Io.Threaded` init, thread the `io` handle), `term.zig`, `theme.zig`, `ui.zig`, `archinstall.zig`,
   `cidata.zig`. Signatures gain an `io: std.Io` parameter where J06's inventory says so; no behaviour change.
   Use the 0.16 std sources (`/usr/lib/zig/std/Io.zig`, `Io/Dir.zig`, `Io/File.zig`) as the reference, not memory.
3. `minimum_zig_version = "0.16.0"`.
4. `zig fmt --check src/`, `zig build`, `zig build test --summary all` on 0.16 — the five tests J06 left plus
   cidata's four if the root test step now reaches them (say which).
5. Render check exactly as J06 did: first-frame captures in truecolor/ansi16/nocolor from the 0.14.1 binary at
   main (`~/.cache/lead-zig/current/zig` is on this machine, or fetch 0.14.1 as J06 did) and from your 0.16 binary;
   `cmp` each pair.

## Acceptance
1. `zig build test --summary all` on 0.16 with all tests passing, named.
2. The three `cmp` results, identical.
3. `git diff --stat main` and a count of changed lines against J06's 110-140 estimate.
4. `./tests/run.sh` tail, unchanged, and `tests/test_file_length.sh` ok (no src file over 600).

## Out of scope
- Any new screen, any archinstall behaviour, `post_install.sh`, `installer/build.zig` beyond what the port forces.
- Keeping 0.14 compatibility (0.16 is the only toolchain that matters after this).

## Stop conditions
- If a stdlib API you need has no 0.16 equivalent, stop and name it with the call site.
- If the port crosses 250 changed lines, stop and report where the estimate broke.
