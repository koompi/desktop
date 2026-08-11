#!/usr/bin/env bash
# The shell-services workspace was built one crate per job, each verified once by
# hand against a live session. This is the half of that verification a test can
# carry: the rules the crates were built under, made mechanical, plus the builds.
#
# Neither toolchain is required. setups.sh installs the shell on a machine with
# no cargo and no zig, so a machine with neither has nothing to prove here. The
# source-level checks still run in that case, since a file is present whether or
# not anything can compile it.
#
# The demos are deliberately not run. They connect to the live session and
# several stream until killed; clippy --all-targets already proves they compile.
# The #[ignore]d tests stay ignored for the same reason: they want a private
# dbus-daemon, a live inhibitor or the user's seat, and the tray watcher ones
# would take the tray off the desktop of whoever runs ./tests/run.sh.
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
WS="$ROOT/shell-services"
UI_PATTERN='gtk|qt|iced|winit|egui|slint|image|png|svg|reqwest|hyper'

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
skip() { printf 'skip: %s\n' "$1"; }

[[ -f "$WS/Cargo.toml" ]] || { skip "no shell-services workspace; nothing to check"; exit 0; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

declared_members() {
    sed -n '/^members = \[/,/^]/p' "$WS/Cargo.toml" | grep -oE '"[^"]+"' | tr -d '"' | sort
}

present_members() {
    for dir in "$WS"/*/; do
        [[ -f "$dir/Cargo.toml" ]] && basename -- "$dir"
    done | sort
}

declared_members > "$tmp/declared"
present_members > "$tmp/present"
[[ -s "$tmp/declared" ]] || fail "no members = [...] list found in shell-services/Cargo.toml"

missing="$(comm -23 "$tmp/declared" "$tmp/present" | tr '\n' ' ')"
[[ -z "${missing// }" ]] \
    || fail "workspace members with no crate directory: $missing"
unlisted="$(comm -13 "$tmp/declared" "$tmp/present" | tr '\n' ' ')"
[[ -z "${unlisted// }" ]] \
    || fail "crate directories missing from the members list in shell-services/Cargo.toml: $unlisted"

printf -- '--- %s members\n' "$(wc -l < "$tmp/present")"

# Every dependency key a manifest declares, across [dependencies],
# [dev-dependencies], [workspace.dependencies], a target table, and the
# [dependencies.name] form. Reads the keys rather than the whole file so that a
# name in a description or a doc link is not mistaken for a dependency.
manifest_deps() {
    awk '
        /^\[/ {
            in_deps = ($0 ~ /dependencies\]$/)
            if ($0 ~ /^\[[^]]*dependencies\./) {
                name = $0; sub(/.*dependencies\./, "", name); sub(/\].*/, "", name); print name
            }
            next
        }
        in_deps && /^[A-Za-z0-9_-]+[ .=]/ { name = $0; sub(/[ .=].*/, "", name); print name }
    ' "$1" | sort -u
}

# One shared crate and nothing else. Two crates needing the same type is a signal
# it belongs in koompi-service, not a reason for them to depend on each other.
# shelld is the exception the rule is for: it exists to consume the others, and it
# is the only member allowed to, which is what keeps the dependency edges pointing
# one way instead of into a mesh.
while read -r member; do
    [[ "$member" == shelld ]] && continue
    manifest_deps "$WS/$member/Cargo.toml" | grep '^koompi-' > "$tmp/deps"
    while read -r dep; do
        [[ "$dep" == koompi-service ]] \
            || fail "$member depends on $dep; koompi-service is the only cross-crate dependency allowed"
    done < "$tmp/deps"
done < "$tmp/present"

# Nothing may depend on the daemon: it is a binary, and a crate reaching for it is
# a crate that has started routing through the shell's transport.
while read -r member; do
    manifest_deps "$WS/$member/Cargo.toml" | grep -qx 'koompi-shelld' \
        && fail "$member depends on koompi-shelld, which is the daemon rather than a library"
done < "$tmp/present"

# No UI dependency, ever: no toolkit, no windowing library, no drawing or decoding
# crate, no http client. Checked in the manifests as well as in the tree below,
# because a name declared in [workspace.dependencies] that no member has taken up
# yet resolves to nothing and so never appears in cargo tree.
{
    manifest_deps "$WS/Cargo.toml"
    while read -r member; do manifest_deps "$WS/$member/Cargo.toml"; done < "$tmp/present"
} | sort -u | grep -Ei "$UI_PATTERN" > "$tmp/ui_declared"
if [[ -s "$tmp/ui_declared" ]]; then
    fail "a UI or decoding dependency is declared in the manifests: $(tr '\n' ' ' < "$tmp/ui_declared")"
fi

# Every crate here replaced a fork of hyprctl, busctl, playerctl, nmcli, loginctl
# or rfkill with a socket or a bus call. Two are exempt and stay named: audio
# spawns the zig audiod, and brightness keeps ddcutil for external panels, which
# have no logind path. Adding a third means changing this line.
subprocess_free=(bluetooth hyprland mpris network notifications power session shelld tray)
printf '%s\n' "${subprocess_free[@]}" | sort > "$tmp/free_expected"
grep -vxE 'service|audio|brightness' "$tmp/present" > "$tmp/free_actual"
if ! diff -q "$tmp/free_expected" "$tmp/free_actual" > /dev/null; then
    fail "the subprocess-free list has drifted from the members: $(diff "$tmp/free_expected" "$tmp/free_actual" | tr '\n' ' ')"
fi

while read -r member; do
    hits="$(grep -rn 'Command::new' "$WS/$member/src" "$WS/$member/examples" 2> /dev/null)"
    [[ -z "$hits" ]] \
        || fail "koompi-$member spawns a subprocess again, and removing one is what the crate was for: $hits"
done < "$tmp/free_actual"

# koompi-service is the shared shape and reads nothing, so it has no demo, and
# shelld is a daemon rather than a library: running it against a real session is
# what it does. Every crate that talks to the system has one.
while read -r member; do
    [[ "$member" == service || "$member" == shelld ]] && continue
    [[ -f "$WS/$member/examples/demo.rs" ]] \
        || fail "koompi-$member has no examples/demo.rs, so nothing shows it against a real session"
done < "$tmp/present"

# The daemon is the only member the shell actually spawns, so its wire format is a
# consumer-visible contract in a way the crates' APIs are not.
[[ -f "$WS/shelld/PROTOCOL.md" ]] \
    || fail "shelld has no PROTOCOL.md, and the document rather than the Rust is what a consumer implements against"

echo "ok   structure: members, no cross-crate deps, no subprocesses, demos present"

if ! command -v cargo > /dev/null; then
    skip "no cargo; the workspace was not built, tested or linted"
else
    # --locked throughout: J01 declared every dependency up front so the panes could
    # run in parallel, which makes Cargo.lock moving a regression in itself.
    printf -- '--- cargo tree\n'
    if ! (cd "$WS" && cargo tree --workspace --locked) > "$tmp/tree.log" 2>&1; then
        tail -20 "$tmp/tree.log"
        fail "cargo tree failed; if it asks to update Cargo.lock, that is the finding"
    fi
    # Names only. A repo path containing one of these words is not a dependency on it.
    ui="$(sed -E 's/^[^[:alnum:]]*//' "$tmp/tree.log" | cut -d' ' -f1 | sort -u \
        | grep -Ei "$UI_PATTERN" | tr '\n' ' ')"
    [[ -z "${ui// }" ]] \
        || fail "a UI or decoding dependency reached the service layer, transitively or directly: $ui"
    echo "ok   no toolkit, windowing, drawing or http dependency in the tree"

    printf -- '--- cargo test\n'
    (cd "$WS" && cargo test --workspace --locked --quiet) > "$tmp/test.log" 2>&1
    rc=$?
    grep -hE '^test result' "$tmp/test.log" \
        | awk '{p += $4; f += $6; i += $8} END {printf "     %d passed, %d failed, %d ignored\n", p, f, i}'
    [[ $rc -eq 0 ]] || { tail -30 "$tmp/test.log"; fail "shell-services tests failed"; }

    printf -- '--- cargo clippy\n'
    if ! (cd "$WS" && cargo clippy --workspace --all-targets --locked -- -D warnings) > "$tmp/clippy.log" 2>&1; then
        tail -30 "$tmp/clippy.log"
        fail "shell-services is not clippy clean at -D warnings"
    fi
    echo "ok   workspace builds, tests and lints clean"

    # The suite is read-only against the seat by construction, stated in its own
    # docstring, so it is safe to run here. Without a system bus every check fails
    # for the wrong reason.
    if [[ ! -S /run/dbus/system_bus_socket ]]; then
        skip "no system bus; the shelld conformance suite needs NetworkManager and UPower to answer"
    elif ! command -v python3 > /dev/null; then
        skip "no python3; the shelld conformance suite did not run"
    else
        printf -- '--- shelld conformance\n'
        (cd "$WS" && cargo build -p koompi-shelld --locked) > "$tmp/shelld-build.log" 2>&1 \
            || { tail -20 "$tmp/shelld-build.log"; fail "koompi-shelld does not build"; }
        SHELLD="$WS/target/debug/koompi-shelld" timeout 300 python3 "$WS/shelld/tests/test_shelld.py" \
            > "$tmp/shelld.log" 2>&1
        rc=$?
        tail -1 "$tmp/shelld.log"
        [[ $rc -eq 0 ]] || { tail -40 "$tmp/shelld.log"; fail "koompi-shelld failed its conformance suite"; }
    fi
fi

if [[ ! -f "$ROOT/audiod/build.zig" ]]; then
    skip "no audiod/; the zig half is absent"
elif ! command -v zig > /dev/null; then
    skip "no zig; audiod was not built and its conformance suite did not run"
else
    printf -- '--- zig build\n'
    (cd "$ROOT/audiod" && zig build) > "$tmp/zig.log" 2>&1 \
        || { tail -30 "$tmp/zig.log"; fail "audiod does not build"; }
    echo "ok   audiod builds"

    # The suite reads by default and restores what it touches, so it is safe here,
    # but without a running PipeWire every check fails for the wrong reason.
    if ! compgen -G "${XDG_RUNTIME_DIR:-/nonexistent}/pipewire-*" > /dev/null; then
        skip "no pipewire socket under XDG_RUNTIME_DIR; the audiod conformance suite needs a live PipeWire"
    elif ! command -v python3 > /dev/null; then
        skip "no python3; the audiod conformance suite did not run"
    else
        printf -- '--- audiod conformance\n'
        AUDIOD="$ROOT/audiod/zig-out/bin/audiod" timeout 300 python3 "$ROOT/audiod/tests/test_audiod.py" \
            > "$tmp/audiod.log" 2>&1
        rc=$?
        tail -1 "$tmp/audiod.log"
        [[ $rc -eq 0 ]] || { tail -30 "$tmp/audiod.log"; fail "audiod failed its conformance suite"; }
    fi
fi

echo "ok"
